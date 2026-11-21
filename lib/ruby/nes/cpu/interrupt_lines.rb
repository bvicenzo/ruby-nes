# frozen_string_literal: true

require_relative 'nmi_detector'
require_relative 'irq_line'

module Ruby
  module Nes
    class Cpu
      # The CPU's NMI and IRQ inputs (https://www.nesdev.org/wiki/CPU_interrupts) and the poll that decides which
      # interrupt a step takes. The NMI's edge is Cpu::NmiDetector's; the IRQ's wired-OR level is Cpu::IrqLine's; this
      # class is the arbiter: the cycle the poll looks at, the I it sees, and the priority, "If both an NMI and an IRQ
      # are pending at the end of an instruction, the NMI will be handled". The IRQ is masked by I and stays as long as
      # its line.
      #
      # What a poll sees is "the status of the interrupt lines at the end of the second-to-last cycle" of the previous
      # instruction (plan 12, decision 2): a step starting on `cycle` sees the changes that came before `cycle - 1`.
      # Plan 22 adds its exceptions, each told by the instruction and used by the next poll only:
      #
      # - "The CLI, SEI, and PLP instructions on the other hand change the I flag after polling for interrupts", so
      #   the poll that follows them sees the I from before them (`poll_with_interrupt_disable`). RTI changes I first.
      # - Branches poll "before the second CPU cycle (the operand fetch)", and a taken branch not before the third, so
      #   one that does not cross a page polls one cycle earlier than usual (`poll_one_cycle_early`); one that crosses
      #   polls again before its fix-up cycle, the usual point.
      # - BRK and the interrupt sequence pick their vector after tick 4, so an NMI by then hijacks them
      #   (`hijacked_vector`): "an NMI can hijack an IRQ".
      # - A DMA halts the CPU after the instruction polled, and the halted CPU polls nothing, so the next poll looks
      #   back past the stall (`poll_before_stall`; cpu_interrupts_v2's 4-irq_and_dma, plan 22 decision 9).
      # - "The interrupt sequences themselves do not perform interrupt polling, meaning at least one instruction from
      #   the interrupt handler will execute before another interrupt is serviced" (`skip_next_poll`).
      class InterruptLines
        # The poll sees changes up to the cycle before the previous instruction's last one.
        POLL_DELAY_CYCLES = 1
        # BRK and the interrupt sequence pick their vector after their fourth tick.
        HIJACK_TICKS = 4
        # The IRQ sources, one bit each: the cartridge board (MMC3, plan 21) and the APU's frame counter (plan 22). Plan
        # 23 adds the DMC's.
        MAPPER_IRQ = 0x01
        FRAME_IRQ = 0x02

        def initialize(status:, nmi_detector: NmiDetector.new, irq_line: IrqLine.new)
          @status = status
          @nmi_detector = nmi_detector
          @irq_line = irq_line
          @held_interrupt_disable = nil
          @early_poll_cycles = 0
          @skip_poll = false
        end

        # The NMI line's new level, `true` while asserted, and the CPU cycle the change happened on.
        def nmi_line_changed(asserted, cycle)
          @nmi_detector.line_changed(asserted, cycle)
        end

        # The source pulls the IRQ line low on `cycle`.
        def assert_irq(source, cycle)
          @irq_line.assert(source, cycle)
        end

        # The source lets go of the IRQ line on `cycle`.
        def release_irq(source, cycle)
          @irq_line.release(source, cycle)
        end

        # CLI, SEI and PLP: the next poll sees `interrupt_disable` as it was before them.
        def poll_with_interrupt_disable(interrupt_disable)
          @held_interrupt_disable = interrupt_disable
        end

        # A taken branch that does not cross a page: the next poll looks one cycle earlier.
        def poll_one_cycle_early
          @early_poll_cycles = 1
        end

        # A DMA halted the CPU for `stall_cycles` after the instruction: the next poll looks back past them.
        def poll_before_stall(stall_cycles)
          @early_poll_cycles += stall_cycles
        end

        # BRK or an interrupt sequence ran: the next step runs the handler's first instruction without polling.
        def skip_next_poll
          @skip_poll = true
        end

        # The vector of the interrupt a step starting on `cycle` takes, or nil, without taking it (for the tracer).
        def pending(cycle)
          return if @skip_poll

          poll_cycle = cycle - POLL_DELAY_CYCLES - @early_poll_cycles
          if @nmi_detector.pending_before?(poll_cycle)
            NMI_VECTOR
          elsif !interrupt_disable_seen? && @irq_line.asserted_at?(poll_cycle)
            IRQ_VECTOR
          end
        end

        # The vector of the interrupt to take at the start of `cycle`, or nil. Taking an NMI clears it; an IRQ stays as
        # long as its line. The poll's exceptions apply to this poll only.
        def acknowledge(cycle)
          vector = pending(cycle)
          @nmi_detector.clear_pending if vector == NMI_VECTOR
          @held_interrupt_disable = nil
          @early_poll_cycles = 0
          @skip_poll = false
          vector
        end

        # The vector a BRK or interrupt sequence started on `start_cycle` loads: the NMI's when its edge came by the
        # sequence's fourth tick, which takes it, and `vector` otherwise.
        def hijacked_vector(vector, start_cycle)
          return vector unless @nmi_detector.pending_before?(start_cycle + HIJACK_TICKS)

          @nmi_detector.clear_pending
          NMI_VECTOR
        end

        # Reset forgets an NMI not yet taken (plan 07, decision 6) and the poll's exceptions the instructions before it
        # told; the lines keep the levels their devices set.
        def reset
          @nmi_detector.clear_pending
          @held_interrupt_disable = nil
          @early_poll_cycles = 0
          @skip_poll = false
        end

        private

        def interrupt_disable_seen?
          @held_interrupt_disable.nil? ? @status.interrupt_disable? : @held_interrupt_disable
        end
      end
    end
  end
end
