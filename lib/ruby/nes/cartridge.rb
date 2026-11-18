# frozen_string_literal: true

module Ruby
  module Nes
    Cartridge = Data.define(:header, :prg_rom, :chr_rom, :trainer)

    # A loaded iNES image (https://www.nesdev.org/wiki/INES): the decoded header and the cartridge memories as frozen
    # arrays of bytes. `chr_rom` is empty on boards with CHR RAM, and `trainer` is empty when the image has none.
    # Built by Cartridge::Loader.
    class Cartridge
      # Base class of every error raised while reading an iNES image.
      class Error < Nes::Error; end

      # The bytes are not an iNES image: shorter than the header, or without the "NES" + $1A magic.
      class InvalidImage < Error; end

      # The header declares more trainer, PRG ROM and CHR ROM bytes than the image holds.
      class TruncatedImage < Error; end
    end
  end
end

require_relative 'cartridge/header'
require_relative 'cartridge/loader'
