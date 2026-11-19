# frozen_string_literal: true

module Ruby
  module Nes
    class CpuBus
      # The 2A03's OAM DMA unit (https://www.nesdev.org/wiki/DMA), started by a write to OAMDMA ($4014) with a page
      # number. It "copies 256 bytes from a CPU page to PPU OAM via the OAMDATA ($2004) register", "forward from the start
      # of the page", so the bytes land from OAMADDR on and wrap around OAM. The copy happens at once; the CPU pays for it
      # afterwards: the DMA "halts the CPU, performs an optional alignment cycle, and then gets and puts 256 times, taking
      # 513 or 514 cycles", which `take_stall_cycles` reports for Cpu#step to add.
      #
      # Get cycles "are aligned to the first and second halves of the APU clock", and "At power-on, whether the first CPU
      # cycle is get or put is random". By convention an even CPU cycle, counted from `Cpu.new`, is a get cycle (plan 11,
      # decision 3, which compares it with Mesen2's arithmetic). The $4014 write is the cycle before the halt: on a get
      # cycle no alignment is needed (513 cycles), on a put cycle one is (514).
      class OamDma
        # A page holds as many bytes as a byte has values.
        PAGE_SIZE = Bits::BYTE_RANGE
        # One halt cycle, then 256 get/put pairs.
        ALIGNED_STALL_CYCLES = 513
        # The same, after one alignment cycle.
        MISALIGNED_STALL_CYCLES = 514

        def initialize(bus:, ppu_registers:)
          @bus = bus
          @ppu_registers = ppu_registers
          @pending = false
        end

        # Copies the page `page`00-`page`FF to OAMDATA.
        def start(page)
          page_start = page << 8 # glossary: combine-bytes
          offset = 0
          while offset < PAGE_SIZE
            @ppu_registers.cpu_write(Ppu::OAMDATA, @bus.read(page_start | offset)) # glossary: combine-bytes
            offset += 1
          end
          @pending = true
        end

        # The cycles the CPU stays halted for a DMA started since the last call, 0 when there is none. `halt_cycle` is
        # the CPU cycle the halt falls on: the number of cycles the CPU has run so far.
        def take_stall_cycles(halt_cycle)
          return 0 unless @pending

          @pending = false
          halt_cycle.odd? ? ALIGNED_STALL_CYCLES : MISALIGNED_STALL_CYCLES
        end
      end
    end
  end
end
