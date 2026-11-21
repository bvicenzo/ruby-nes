# frozen_string_literal: true

module Ruby
  module Nes
    module Mappers
      class Mmc3 < Base
        # Watches PPU address line A12 for MMC3's counter (https://www.nesdev.org/wiki/MMC3#IRQ_Specifics): it is
        # clocked "on a rising edge after the line has remained low for three falling edges of M2", "no matter what
        # caused it". The board hands it every address that reaches it: pattern fetches, PPUDATA accesses and v left on
        # the bus (plan 21, decision 1). M2 cycles are the PPU's elapsed dots divided by 3, counted from the first low
        # address after a high one (plan 21, decision 2): an approximation of the edges, whose phase within a CPU cycle
        # is not modelled. A12 starts low since dot 0, a convention (plan 21, decision 13). Hot path: called on every
        # pattern fetch; integers only.
        class A12Watcher
          # Address bit 12.
          A12_FLAG = 0x1000
          # "three falling edges of M2".
          LOW_M2_CYCLES = 3

          attr_writer :ppu

          def initialize(counter:, ppu: nil)
            @counter = counter
            @ppu = ppu
            @high = false
            @low_since = 0
          end

          def watch(address)
            if address.anybits?(A12_FLAG)
              rise unless @high
            elsif @high
              @high = false
              @low_since = m2_cycle
            end
          end

          private

          def rise
            @high = true
            cycle = m2_cycle
            @counter.clock(cycle) if cycle - @low_since >= LOW_M2_CYCLES
          end

          def m2_cycle = @ppu.elapsed_dots / Ppu::DOTS_PER_CPU_CYCLE
        end
      end
    end
  end
end
