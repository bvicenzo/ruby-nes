# frozen_string_literal: true

module Ruby
  module Nes
    class Cpu
      module Instructions
        # Loads and stores (https://www.nesdev.org/wiki/Instruction_reference), included in Cpu. Each takes the
        # effective address its addressing mode resolved. Loads set Z and N from the loaded byte; stores change no flag.
        # LAX and SAX are unofficial (https://www.nesdev.org/wiki/Programming_with_unofficial_opcodes).
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

          # LAX: "Shortcut for LDA value then TAX".
          def load_accumulator_and_index_x(address)
            @accumulator = @index_x = @bus.read(address)
            @status.update_zero_and_negative(@accumulator)
          end

          # SAX: "Stores the bitwise AND of A and X. As with STA and STX, no flags are affected."
          def store_accumulator_and_index_x(address)
            @bus.write(address, @accumulator & @index_x) # glossary: bitwise-and
          end
        end
      end
    end
  end
end
