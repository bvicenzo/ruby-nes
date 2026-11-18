# frozen_string_literal: true

# Builds a Ruby::Nes::Cartridge in memory, without an iNES image: the header's sizes follow the arrays given, and
# every flag a mapper does not read stays at its iNES 1.0 default. By default it is the smallest valid NROM cartridge
# (16 KiB of PRG ROM, 8 KiB of CHR ROM); each example passes only what its cause is about. An empty `chr_rom` is a
# board with CHR RAM. The arrays are copied before being frozen, so the caller's stay untouched.
#
#   Cartridges.build(chr_rom: [], mirroring: :vertical)
module Cartridges
  def self.build(prg_rom: Array.new(16_384, 0xEA), chr_rom: Array.new(8_192, 0x00), mirroring: :horizontal,
                 mapper_number: 0)
    header = Ruby::Nes::Cartridge::Header.new(
      prg_rom_size: prg_rom.size,
      chr_rom_size: chr_rom.size,
      mirroring:,
      battery: false,
      trainer: false,
      alternative_nametables: false,
      nes2: false,
      mapper_number:
    )

    Ruby::Nes::Cartridge.new(header:, prg_rom: prg_rom.dup.freeze, chr_rom: chr_rom.dup.freeze, trainer: [].freeze)
  end
end
