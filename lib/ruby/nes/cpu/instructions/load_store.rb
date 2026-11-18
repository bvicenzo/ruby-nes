# frozen_string_literal: true

module Ruby
  module Nes
    class Cpu
      module Instructions
        # Loads and stores (https://www.nesdev.org/wiki/Instruction_reference), included in Cpu. Each takes the
        # effective address its addressing mode resolved. Loads set Z and N from the loaded byte; stores change no flag.
        module LoadStore
          # LDA
          def load_accumulator(address)
            @accumulator = @bus.read(address)
            @status.update_zero_and_negative(@accumulator)
          end

          # LDX
          def load_index_x(address)
            @index_x = @bus.read(address)
            @status.update_zero_and_negative(@index_x)
          end

          # LDY
          def load_index_y(address)
            @index_y = @bus.read(address)
            @status.update_zero_and_negative(@index_y)
          end

          # STA
          def store_accumulator(address)
            @bus.write(address, @accumulator)
          end

          # STX
          def store_index_x(address)
            @bus.write(address, @index_x)
          end

          # STY
          def store_index_y(address)
            @bus.write(address, @index_y)
          end
        end
      end
    end
  end
end
