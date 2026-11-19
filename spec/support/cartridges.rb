# frozen_string_literal: true

# Builds a Ruby::Nes::Cartridge in memory, without an iNES image: the header's sizes follow the arrays given, and
# every flag a mapper does not read stays at its iNES 1.0 default. By default it is the smallest valid NROM cartridge
# (16 KiB of PRG ROM, 8 KiB of CHR ROM); each example passes only what its cause is about. An empty `chr_rom` is a
# board with CHR RAM. The arrays are copied before being frozen, so the caller's stay untouched.
#
#   Cartridges.build(chr_rom: [], mirroring: :vertical)
#   Cartridges.with_program([0x4C, 0x00, 0x80], interrupt_handler: [0xE6, 0x10, 0x40])
module Cartridges
  PRG_ROM_SIZE = 16_384
  # The 16 KiB of PRG ROM appear at $8000 and again at $C000 (https://www.nesdev.org/wiki/NROM).
  PROGRAM_START = 0x8000
  INTERRUPT_HANDLER_START = 0x9000
  # $FFFA-$FFFF: the NMI, reset and IRQ vectors (https://www.nesdev.org/wiki/CPU_interrupts), little-endian.
  VECTORS_OFFSET = 0x3FFA
  VECTORS = [0x00, 0x90, 0x00, 0x80, 0x00, 0x90].freeze
  # RTI.
  RETURN_FROM_INTERRUPT = [0x40].freeze

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

  # An NROM cartridge whose program starts at $8000, the reset vector, and whose NMI and IRQ vectors point at the
  # interrupt handler at $9000 (RTI unless given). The rest of PRG ROM is NOP.
  def self.with_program(program, interrupt_handler: RETURN_FROM_INTERRUPT)
    prg_rom = Array.new(PRG_ROM_SIZE, 0xEA)
    prg_rom[0, program.size] = program
    prg_rom[INTERRUPT_HANDLER_START - PROGRAM_START, interrupt_handler.size] = interrupt_handler
    prg_rom[VECTORS_OFFSET, VECTORS.size] = VECTORS
    build(prg_rom:)
  end
end
