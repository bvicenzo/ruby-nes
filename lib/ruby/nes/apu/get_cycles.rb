# frozen_string_literal: true

module Ruby
  module Nes
    class Apu
      # The CPU cycles the pulse, noise and DMC timers tick on: once per APU cycle, "2 CPU cycles = 1 APU cycle"
      # (https://www.nesdev.org/wiki/APU_Frame_Counter), on the even cycles, the get cycles (plan 22, decision 5). The
      # sync deadline and the runs count those ticks in CPU cycles (plan 29). Hot path: called once per run.
      module GetCycles
        # The CPU cycle of tick `ticks` (0 is the first) counted from CPU cycle `cycle`.
        def self.cycle_of_tick(cycle, ticks)
          cycle + (cycle.odd? ? 1 : 0) + (ticks * CPU_CYCLES_PER_APU_CYCLE)
        end

        # The ticks among the `cycles` CPU cycles from `cycle` on.
        def self.count(cycle, cycles)
          (cycles + (cycle.odd? ? 0 : 1)) / CPU_CYCLES_PER_APU_CYCLE
        end
      end
    end
  end
end
