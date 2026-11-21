# frozen_string_literal: true

module Ruby
  module Nes
    class Cpu
      # Reset, NMI and IRQ (https://www.nesdev.org/wiki/CPU_interrupts), included in Cpu. Every interrupt goes through
      # the same seven-tick sequence: push the program counter, push the status, set I, load the program counter from
      # the vector.
      module Interrupts
        INTERRUPT_CYCLES = 7
        # Reset "suppresses writes, decrementing the stack pointer thrice without modifying memory".
        RESET_SUPPRESSED_PUSHES = 3

        # Reset, and with a freshly built CPU (every register zero) the power-up state
        # (https://www.nesdev.org/wiki/CPU_power_up_state): S moves down three bytes without writing, I is set and the
        # program counter comes from $FFFC; A, X, Y and the other flags are unchanged. A pending NMI is discarded (plan
        # 07, decision 6). It also releases a CPU a JAM opcode halted (plan 09). Returns the cycles it took, 7, as #step
        # does.
        def reset
          @jammed = false
          @stack.pointer = Bits.wrap_to_byte(@stack.pointer - RESET_SUPPRESSED_PUSHES)
          @status.interrupt_disable = true
          @program_counter = read_word(RESET_VECTOR)
          @interrupt_lines.discard_pending_nmi
          @cycles += INTERRUPT_CYCLES
          INTERRUPT_CYCLES
        end

        # The NMI input changed: `true` while asserted, `false` while released (booleans only), with the CPU cycle the
        # change happened on; the CPU detects its edge and polls it (see InterruptLines).
        def nmi_line_changed(asserted, cycle)
          @interrupt_lines.nmi_line_changed(asserted, cycle)
        end

        # The vector of the interrupt the next step takes, or nil, without taking it: the tracer shows it as a step.
        def pending_interrupt = @interrupt_lines.pending(@cycles)

        # A source (InterruptLines::MAPPER_IRQ…) pulls the IRQ input low; see InterruptLines for the wired-OR.
        def assert_irq(source)
          @interrupt_lines.assert_irq(source)
        end

        # The source lets go of the IRQ input; it stays asserted while another source asserts it.
        def release_irq(source)
          @interrupt_lines.release_irq(source)
        end

        private

        # NMI or IRQ, taken by #step instead of an instruction: the return address is the instruction that would have
        # run, and the flags go with B clear.
        def take_interrupt(vector)
          enter_interrupt(@program_counter, @status.byte_pushed_by_interrupt, vector)
          @cycles += INTERRUPT_CYCLES
        end

        # The sequence BRK, NMI and IRQ share: the return address (high byte first), then the status byte, then I is
        # set and the program counter loads from the vector. Cycles are charged by the caller: BRK through the opcode
        # table, NMI and IRQ through INTERRUPT_CYCLES.
        def enter_interrupt(return_address, pushed_status, vector)
          @stack.push_word(return_address)
          @stack.push(pushed_status)
          @status.interrupt_disable = true
          @program_counter = read_word(vector)
        end
      end
    end
  end
end
