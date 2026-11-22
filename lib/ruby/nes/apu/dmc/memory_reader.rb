# frozen_string_literal: true

module Ruby
  module Nes
    class Apu
      class Dmc
        # The DMC's memory reader (https://www.nesdev.org/wiki/APU_DMC): the 1-byte sample buffer, filled by DMA
        # whenever it is empty and the sample has bytes remaining. A fill reads the byte at the sample's address as the
        # DMA unit reads (CpuBus#read_for_dma), halts the CPU (https://www.nesdev.org/wiki/DMA: 3 cycles for a load
        # after a $4015 write, 4 for a reload after the output unit took the byte; plan 23, decisions 1-3) and advances
        # the sample. The bus and the CPU are given through writers, as the Console builds them after the APU: until
        # then a $4015 write that starts a sample has nothing to read from. Hot path: the output unit takes a byte every
        # eight timer clocks.
        class MemoryReader
          # "Load DMAs take 3 cycles and reload DMAs take 4".
          LOAD_STALL_CYCLES = 3
          RELOAD_STALL_CYCLES = 4

          attr_writer :memory, :cpu

          def initialize(sample:, memory: nil, cpu: nil)
            @sample = sample
            @memory = memory
            @cpu = cpu
            @buffer = nil
          end

          # $4015 with the DMC bit set, on `cycle`: the sample restarts "only if its bytes-remaining counter is 0", and
          # an empty buffer is filled at once.
          def start(cycle)
            @sample.restart unless @sample.active?
            fill(LOAD_STALL_CYCLES, cycle)
          end

          # $4015 with the DMC bit clear: the sample ends; the buffer keeps its byte.
          def stop
            @sample.stop
          end

          # The output unit takes the buffer's byte on `cycle`, nil when it is empty; the buffer is filled again.
          def take_sample(cycle)
            byte = @buffer
            @buffer = nil
            fill(RELOAD_STALL_CYCLES, cycle)
            byte
          end

          def active? = @sample.active?

          private

          def fill(stall_cycles, cycle)
            return unless @buffer.nil? && @sample.active?

            @buffer = @memory.read_for_dma(@sample.address)
            @cpu.halt(stall_cycles)
            @sample.advance(cycle)
          end
        end
      end
    end
  end
end
