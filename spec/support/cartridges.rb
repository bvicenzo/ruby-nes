# frozen_string_literal: true

# Builds a Ruby::Nes::Cartridge in memory, without an iNES image: the header's sizes follow the arrays given, and
# every flag a mapper does not read stays at its iNES 1.0 default. By default it is the smallest valid NROM cartridge
# (16 KiB of PRG ROM, 8 KiB of CHR ROM); each example passes only what its cause is about. An empty `chr_rom` is a
# board with CHR RAM. The arrays are copied before being frozen, so the caller's stay untouched.
#
#   Cartridges.build(chr_rom: [], mirroring: :vertical)
#   Cartridges.build(mapper_number: 1, battery: true)
#   Cartridges.with_program([0x4C, 0x00, 0x80], interrupt_handler: [0xE6, 0x10, 0x40])
module Cartridges
  PRG_ROM_SIZE = 16_384
  CHR_ROM_SIZE = 8_192
  # NOP, what PRG ROM holds wherever a spec puts nothing.
  NO_OPERATION = 0xEA
  # The 16 KiB of PRG ROM appear at $8000 and again at $C000 (https://www.nesdev.org/wiki/NROM).
  PROGRAM_START = 0x8000
  INTERRUPT_HANDLER_START = 0x9000
  # $FFFA-$FFFF: the NMI, reset and IRQ vectors (https://www.nesdev.org/wiki/CPU_interrupts), little-endian words.
  VECTORS_OFFSET = 0x3FFA
  VECTORS = [INTERRUPT_HANDLER_START, PROGRAM_START, INTERRUPT_HANDLER_START].pack('v*').bytes.freeze
  # RTI.
  RETURN_FROM_INTERRUPT = [0x40].freeze

  # One optional keyword per memory and header field a board reads, so each spec passes only its cause's.
  # rubocop:disable-next Metrics/ParameterLists
  def self.build(
    prg_rom: Array.new(PRG_ROM_SIZE, NO_OPERATION),
    chr_rom: Array.new(CHR_ROM_SIZE, 0x00),
    mirroring: :horizontal,
    mapper_number: 0,
    alternative_nametables: false,
    battery: false
  )
    header = Ruby::Nes::Cartridge::Header.new(
      prg_rom_size: prg_rom.size,
      chr_rom_size: chr_rom.size,
      mirroring:,
      battery:,
      trainer: false,
      alternative_nametables:,
      nes2: false,
      mapper_number:
    )

    Ruby::Nes::Cartridge.new(header:, prg_rom: prg_rom.dup.freeze, chr_rom: chr_rom.dup.freeze, trainer: [].freeze)
  end

  # The iNES image of an NROM cartridge, as a file holds it (https://www.nesdev.org/wiki/INES): the header with one
  # unit of 16 KiB of PRG ROM per 16 KiB given and 8 KiB of CHR ROM, the battery flag of flags 6 when asked, then the
  # PRG ROM and the CHR ROM (zeros).
  def self.ines_image(prg_rom:, battery: false)
    flags6 = battery ? Ruby::Nes::Cartridge::Header::BATTERY_FLAG : 0
    header = [*Ruby::Nes::Cartridge::Header::MAGIC, prg_rom.size / PRG_ROM_SIZE, 1, flags6, *Array.new(9, 0)]
    [*header, *prg_rom, *Array.new(CHR_ROM_SIZE, 0)].pack('C*')
  end

  # A memory of `count` banks of `size` bytes in which every byte holds its bank's number, so whatever a window shows
  # reads as the number of the bank behind it: `numbered_banks(count: 16, size: 16_384)` is 256 KiB of PRG ROM.
  def self.numbered_banks(count:, size:) = Array.new(count) { |bank| Array.new(size, bank) }.flatten

  # An NROM cartridge whose program starts at $8000, the reset vector, and whose NMI and IRQ vectors point at the
  # interrupt handler at $9000 (RTI unless given). The rest of PRG ROM is NOP. Another `mapper_number` puts the same
  # 16 KiB on that board, where it fits (MMC1 shows it at both $8000 and $C000 at power-up); `battery` sets the header's
  # battery flag.
  def self.with_program(program, interrupt_handler: RETURN_FROM_INTERRUPT, mapper_number: 0, battery: false)
    prg_rom = Array.new(PRG_ROM_SIZE, NO_OPERATION)
    prg_rom[0, program.size] = program
    prg_rom[INTERRUPT_HANDLER_START - PROGRAM_START, interrupt_handler.size] = interrupt_handler
    prg_rom[VECTORS_OFFSET, VECTORS.size] = VECTORS
    build(prg_rom:, mapper_number:, battery:)
  end
end
