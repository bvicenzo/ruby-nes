# frozen_string_literal: true

# Variant for decision 3 of docs/architecture.md: the bit operations of the per-instruction path written with
# Ruby::Nes::Bits helpers instead of inline operators with `# glossary:` tags. The path covered is what every
# instruction runs: the opcode and operand fetch, the addressing mode resolvers and CpuBus#read/#write. The
# instructions themselves keep their inline operators, so the measured cost is a lower bound of a full conversion.
# Helpers that Bits does not have yet are added here, named after their glossary anchors.
module Ruby
  module Nes
    module Bits
      BYTE_WIDTH = 8

      def self.combine_bytes(low:, high:) = (high << BYTE_WIDTH) | low

      def self.mirror_down(address, mirror_mask:) = address & mirror_mask

      def self.page_crossed?(base, address) = (base & PAGE_MASK) != (address & PAGE_MASK)

      def self.increment_within_page(pointer) = (pointer & PAGE_MASK) | ((pointer + 1) & BYTE_MASK)

      def self.signed_byte(byte) = byte >= SIGN_BIT ? byte - BYTE_RANGE : byte
    end

    class Cpu
      def fetch_byte
        byte = @bus.read(@program_counter)
        @program_counter = Bits.wrap_to_word(@program_counter + 1)
        byte
      end

      def fetch_word
        low = fetch_byte
        high = fetch_byte
        Bits.combine_bytes(low:, high:)
      end

      private

      def read_word(address)
        low = @bus.read(address)
        high = @bus.read(Bits.wrap_to_word(address + 1))
        Bits.combine_bytes(low:, high:)
      end

      module AddressingModes
        def immediate_address
          address = @program_counter
          @program_counter = Bits.wrap_to_word(@program_counter + 1)
          address
        end

        def zero_page_x_address = Bits.wrap_to_byte(fetch_byte + @index_x)

        def zero_page_y_address = Bits.wrap_to_byte(fetch_byte + @index_y)

        def absolute_x_address = Bits.wrap_to_word(fetch_word + @index_x)

        def absolute_y_address = Bits.wrap_to_word(fetch_word + @index_y)

        def indexed_indirect_address = word_within_page(Bits.wrap_to_byte(fetch_byte + @index_x))

        def indirect_indexed_address = Bits.wrap_to_word(word_within_page(fetch_byte) + @index_y)

        # The offset is fetched first: the target is relative to the program counter after the operand.
        def relative_address
          signed_offset = Bits.signed_byte(fetch_byte)
          Bits.wrap_to_word(@program_counter + signed_offset)
        end

        private

        def word_within_page(pointer)
          low = @bus.read(pointer)
          high = @bus.read(Bits.increment_within_page(pointer))
          Bits.combine_bytes(low:, high:)
        end

        def indexed_for_read(base, index)
          address = Bits.wrap_to_word(base + index)
          @cycles += 1 if Bits.page_crossed?(base, address)
          address
        end
      end
    end

    class CpuBus
      def read(address)
        @data_bus =
          if address < PPU_REGISTERS_START
            @ram[Bits.mirror_down(address, mirror_mask: RAM_MIRROR_MASK)]
          elsif address < IO_REGISTERS_START
            @ppu_registers.cpu_read(Bits.mirror_down(address, mirror_mask: PPU_REGISTER_MIRROR_MASK), @data_bus)
          elsif address < TEST_MODE_START
            @io_registers.cpu_read(address, @data_bus)
          elsif address < CARTRIDGE_START
            @data_bus
          else
            @mapper.cpu_read(address, @data_bus)
          end
      end

      def write(address, value)
        if address < PPU_REGISTERS_START
          @ram[Bits.mirror_down(address, mirror_mask: RAM_MIRROR_MASK)] = value
        elsif address < IO_REGISTERS_START
          @ppu_registers.cpu_write(Bits.mirror_down(address, mirror_mask: PPU_REGISTER_MIRROR_MASK), value)
        elsif address < TEST_MODE_START
          @io_registers.cpu_write(address, value)
        elsif address >= CARTRIDGE_START
          @mapper.cpu_write(address, value)
        end
      end
    end
  end
end
