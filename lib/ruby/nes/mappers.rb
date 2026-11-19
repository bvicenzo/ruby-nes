# frozen_string_literal: true

# The boards are loaded first: the factory's table below refers to them.
require_relative 'mappers/nrom'

module Ruby
  module Nes
    # The cartridge boards (https://www.nesdev.org/wiki/Mapper), one class per iNES mapper number. Every board answers
    # the same interface (docs/architecture.md, Mapper interface):
    #
    # - cpu_read(address, data_bus) -> the byte left on the CPU data bus; `data_bus` itself when the board does not
    #   drive the bus at that address (open bus). Addresses are $4020-$FFFF.
    # - cpu_write(address, value)   -> PRG RAM writes and mapper registers; anything else is ignored.
    # - ppu_read(address)           -> the pattern table byte, for $0000-$1FFF.
    # - ppu_write(address, value)   -> kept by CHR RAM, ignored by CHR ROM.
    # - mirroring                   -> the nametable arrangement the board selects, asked on every nametable access:
    #                                  :horizontal, :vertical, :single_screen_lower, :single_screen_upper or
    #                                  :four_screen.
    # - irq?                        -> whether the board holds the CPU's IRQ line low.
    module Mappers
      # Base class of every error raised while building a board for a cartridge.
      class Error < Nes::Error; end

      # The cartridge's memories do not fit its board: no PRG ROM at all, or sizes the board does not have.
      class InvalidCartridge < Error; end

      # The cartridge's mapper number has no board here yet.
      class UnsupportedMapper < Error; end

      BOARDS = { 0 => Nrom }.freeze

      # The board for the cartridge's mapper number, built with its memories. Raises InvalidCartridge when the
      # cartridge has no PRG ROM (the iNES page does not define a PRG ROM size of 0), and UnsupportedMapper when its
      # mapper number is not in BOARDS.
      def self.build(cartridge)
        raise InvalidCartridge, 'the cartridge has no PRG ROM' if cartridge.prg_rom.empty?

        mapper_number = cartridge.header.mapper_number
        board = BOARDS.fetch(mapper_number) do
          raise UnsupportedMapper, "mapper #{mapper_number} is not supported (supported: #{BOARDS.keys.join(', ')})"
        end
        board.new(cartridge)
      end
    end
  end
end
