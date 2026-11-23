# frozen_string_literal: true

module Ruby
  module Nes
    class Apu
      # The APU frame counter (https://www.nesdev.org/wiki/APU_Frame_Counter): a sequencer ticked once per CPU cycle
      # that clocks the channels' quarter frame (envelopes) and half frame (length counters, sweeps) units at fixed
      # cycles, and in mode 0 sets the frame interrupt flag. Its NTSC table gives APU cycles on their GET or PUT half;
      # in CPU cycles from the sequence's start that is 2 × the APU cycle, plus 1 on PUT (plan 22). Each mode is a pair
      # of constant tables, the cycle of each step and its events, the last step being cycle 0 of the next sequence.
      #
      # A $4017 write tells the inhibit flag (bit 6) to the interrupt at once; the mode (bit 7) and the reset of the
      # sequence take effect 3 CPU cycles after a write on an odd cycle and 4 after one on an even cycle: "during" or
      # "between" APU cycles, with even cycles as GET cycles (plan 22, decision 5), and in mode 1 the reset also clocks
      # a quarter and a half frame. At power it acts as if $00 was written: mode 0, from cycle 0; reset writes the last
      # value again. Hot path: ticked every CPU cycle, integers and constant tables only.
      class FrameCounter
        # A step's events, one bit each.
        QUARTER_FRAME = 0x01
        HALF_FRAME = 0x02
        INTERRUPT = 0x04
        BOTH_FRAMES = QUARTER_FRAME | HALF_FRAME
        # Mode 0 (4-step): 3728 PUT, 7456 PUT, 11185 PUT, 14914 GET, 14914 PUT, 0 (14915) GET.
        FOUR_STEP_CYCLES = [7457, 14_913, 22_371, 29_828, 29_829, 29_830].freeze
        FOUR_STEP_EVENTS = [
          QUARTER_FRAME,
          BOTH_FRAMES,
          QUARTER_FRAME,
          INTERRUPT,
          BOTH_FRAMES | INTERRUPT,
          INTERRUPT
        ].freeze
        # Mode 1 (5-step): 3728 PUT, 7456 PUT, 11185 PUT, 14914 PUT, 18640 PUT, 0 (18641) GET.
        FIVE_STEP_CYCLES = [7457, 14_913, 22_371, 29_829, 37_281, 37_282].freeze
        FIVE_STEP_EVENTS = [QUARTER_FRAME, BOTH_FRAMES, QUARTER_FRAME, 0, BOTH_FRAMES, 0].freeze
        # $4017: `MI-- ----`.
        FIVE_STEP_FLAG = 0x80
        INHIBIT_FLAG = 0x40
        # CPU cycles from a $4017 write to its effect: 3 "during an APU cycle", a write on an odd (PUT) cycle; 4
        # "between APU cycles", on an even (GET) one. Which parity is which is calibrated with cpu_interrupts_v2's
        # 4-irq_and_dma against OAM DMA's get cycles; apu_test passes either way (plan 22, decision 5).
        WRITE_DELAY_DURING_APU_CYCLE = 3
        WRITE_DELAY_BETWEEN_APU_CYCLES = 4

        def initialize(listener:, interrupt:)
          @listener = listener
          @interrupt = interrupt
          @step_cycles = FOUR_STEP_CYCLES
          @step_events = FOUR_STEP_EVENTS
          @step = 0
          @frame_cycle = 0
          @written_value = 0
          @write_delay = 0
        end

        # CPU cycle `cycle` passes.
        def tick(cycle)
          return if write_takes_effect?(cycle)

          @frame_cycle += 1
          return unless @frame_cycle == @step_cycles[@step]

          run_step(@step_events[@step], cycle)
          @step += 1
          return unless @step == @step_cycles.size

          @step = 0
          @frame_cycle = 0
        end

        # A $4017 write on CPU cycle `cycle`.
        def write(value, cycle)
          @interrupt.change_inhibit((value & INHIBIT_FLAG) != 0, cycle) # glossary: flag-set
          @written_value = value
          @write_delay = cycle.odd? ? WRITE_DELAY_DURING_APU_CYCLE : WRITE_DELAY_BETWEEN_APU_CYCLES
        end

        # The CPU cycle of the next tick that may set the interrupt flag, `cycle` being the cycle of the next tick: the
        # tick that reaches mode 0's next interrupt step unless interrupts are inhibited, or sooner the tick a pending
        # write takes effect on, which restarts the sequence; NEVER without either (plan 29, decision 5). The console
        # catches the APU up from there, so the CPU sees the flag on time.
        def next_interrupt_cycle(cycle)
          interrupt_cycle = interrupt_step_cycle(cycle)
          return interrupt_cycle if @write_delay.zero?

          [cycle + @write_delay - 1, interrupt_cycle].min
        end

        # The CPU cycles before the next tick that runs a step or takes a pending write in: a run of quiet cycles skips
        # them at once (plan 29). Hot path: once per run.
        def quiet_cycles
          quiet = @step_cycles[@step] - @frame_cycle - 1
          return quiet if @write_delay.zero?

          [@write_delay - 1, quiet].min
        end

        # `cycles` quiet ticks at once: the frame cycle and a pending write's delay move on as the ticks would.
        def skip(cycles)
          @frame_cycle += cycles
          @write_delay -= cycles unless @write_delay.zero?
        end

        # "At reset, same as above, except last value written to $4017 is written again, rather than $00" (apu_reset's
        # readme; plan 22, decision 4): the mode stays and the sequence restarts.
        def reset(cycle)
          write(@written_value, cycle)
        end

        private

        # The cycle of the tick that reaches the sequence's next step with an interrupt, `cycle` being the next tick's;
        # NEVER while interrupts are inhibited or in mode 1. Asked once per sync deadline: off the hot path.
        def interrupt_step_cycle(cycle)
          return NEVER if @written_value.anybits?(INHIBIT_FLAG)

          step = @step
          step += 1 while step < @step_events.size && @step_events[step].nobits?(INTERRUPT)
          return NEVER if step == @step_events.size

          cycle + @step_cycles[step] - @frame_cycle - 1
        end

        # Counts a pending write down; on its last cycle the sequence restarts instead of advancing.
        def write_takes_effect?(cycle)
          return false if @write_delay.zero?

          @write_delay -= 1
          return false unless @write_delay.zero?

          restart(cycle)
          true
        end

        def restart(cycle)
          @step = 0
          @frame_cycle = 0
          if (@written_value & FIVE_STEP_FLAG) == 0 # glossary: flag-clear
            @step_cycles = FOUR_STEP_CYCLES
            @step_events = FOUR_STEP_EVENTS
          else
            @step_cycles = FIVE_STEP_CYCLES
            @step_events = FIVE_STEP_EVENTS
            run_step(BOTH_FRAMES, cycle)
          end
        end

        def run_step(events, cycle)
          @listener.quarter_frame if (events & QUARTER_FRAME) != 0 # glossary: flag-set
          @listener.half_frame if (events & HALF_FRAME) != 0 # glossary: flag-set
          @interrupt.trigger(cycle) if (events & INTERRUPT) != 0 # glossary: flag-set
        end
      end
    end
  end
end
