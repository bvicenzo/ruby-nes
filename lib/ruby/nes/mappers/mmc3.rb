# frozen_string_literal: true

module Ruby
  module Nes
    module Mappers
      # MMC3, iNES mapper 4 (https://www.nesdev.org/wiki/MMC3): "4 pairs of registers at $8000-$9FFF, $A000-$BFFF,
      # $C000-$DFFF, and $E000-$FFFF", even and odd addresses.
      #
      # - $8000 bank select: bits 2-0 the bank register R0-R7 the next $8001 loads, bit 6 the PRG mode, bit 7 the CHR
      #   A12 inversion. $8001 bank data.
      # - PRG in 8 KiB banks: mode 0 shows R6, R7, the second-last and the last bank at $8000, $A000, $C000, $E000; mode
      #   1 swaps $8000 and $C000 (PRG_LAYOUTS). "R6 and R7 will ignore the top two bits": wrapping around PRG ROM does
      #   the same for every size up to 512 KiB.
      # - CHR: R0 and R1 are 2 KiB banks ("The lowest bit is ignored"), R2-R5 1 KiB banks, at $0000-$0FFF and
      #   $1000-$1FFF, or the other way round with the inversion (CHR_LAYOUTS).
      # - $A000 bit 0: 0 connects CIRAM A10 to PPU A10, vertical mirroring; 1 to A11, horizontal; "no effect on
      #   cartridges with hardwired 4-screen VRAM". The header's mirroring holds until the first write.
      # - $A001, PRG RAM protect, is ignored: "Many emulators choose not to implement them as part of iNES Mapper 004 to
      #   avoid an incompatibility with the MMC6" (plan 21, decision 4). PRG RAM is 8 KiB, always enabled.
      # - $C000 IRQ latch, $C001 IRQ reload, $E000 IRQ disable and acknowledge, $E001 IRQ enable: the IrqCounter, which
      #   the A12Watcher clocks from every address that reaches the board (pattern fetches, PPUDATA, v left on the bus;
      #   plan 21, decision 1).
      #
      # Every register starts at 0 (plan 19, decision 6): R6, R7 and $8000 "are unspecified at power on", and the last
      # bank, fixed at $E000, holds the reset vector. The board needs the CPU (`cpu=`, the IRQ line) and the PPU
      # (`ppu=`, A12's clock) before it renders.
      class Mmc3 < Base
        # Address bits 14-13 pick the pair, bit 0 the register in it: register number = pair × 2 + bit 0.
        PAIR_SELECT_MASK = 0x6000
        PAIR_SELECT_SHIFT = 13
        ODD_ADDRESS_FLAG = 0x0001
        REGISTERS_PER_PAIR = 2
        BANK_SELECT = 0
        BANK_DATA = 1
        MIRRORING = 2
        PRG_RAM_PROTECT = 3
        IRQ_LATCH = 4
        IRQ_RELOAD = 5
        IRQ_DISABLE = 6
        # Bank select: bits 2-0 the bank register, bit 6 the PRG mode, bit 7 the CHR A12 inversion.
        BANK_REGISTER_MASK = 0x07
        PRG_MODE_FLAG = 0x40
        CHR_INVERSION_FLAG = 0x80
        # $A000 bit 0, as the mirroring the PPU bus asks for.
        MIRRORING_FLAG = 0x01
        MIRRORINGS = %i[vertical horizontal].freeze
        # The bank registers R0-R7.
        BANK_REGISTER_COUNT = 8
        R6 = 6
        R7 = 7
        # PRG banks counted from the end of PRG ROM.
        SECOND_LAST_BANK = -2
        LAST_BANK = -1
        PRG_BANK_SIZE = 8_192
        # The source of each 8 KiB window, $8000, $A000, $C000 and $E000, in PRG mode 0 and 1.
        PRG_LAYOUTS = [
          [R6, R7, SECOND_LAST_BANK, LAST_BANK].freeze,
          [SECOND_LAST_BANK, R7, R6, LAST_BANK].freeze
        ].freeze
        TWO_KIB = 2_048
        ONE_KIB = 1_024
        # Each bank register R0-R5 as [the address it shows at, its bank size], without and with the CHR A12 inversion.
        CHR_LAYOUTS = [
          [
            [0x0000, TWO_KIB].freeze,
            [0x0800, TWO_KIB].freeze,
            [0x1000, ONE_KIB].freeze,
            [0x1400, ONE_KIB].freeze,
            [0x1800, ONE_KIB].freeze,
            [0x1C00, ONE_KIB].freeze
          ].freeze,
          [
            [0x1000, TWO_KIB].freeze,
            [0x1800, TWO_KIB].freeze,
            [0x0000, ONE_KIB].freeze,
            [0x0400, ONE_KIB].freeze,
            [0x0800, ONE_KIB].freeze,
            [0x0C00, ONE_KIB].freeze
          ].freeze
        ].freeze

        def initialize(cartridge, irq_counter: IrqCounter.new, a12_watcher: A12Watcher.new(counter: irq_counter))
          super(cartridge, prg_ram: true)
          @irq_counter = irq_counter
          @a12_watcher = a12_watcher
          @four_screen = @mirroring == :four_screen
          @bank_select = 0
          @bank_registers = Array.new(BANK_REGISTER_COUNT, 0)
          select_banks
        end

        def cpu=(cpu)
          super
          @irq_counter.cpu = cpu
        end

        def ppu=(ppu)
          super
          @a12_watcher.ppu = ppu
        end

        # Hot path: one A12 check per pattern fetch, then the base's read.
        def ppu_read(address)
          @a12_watcher.watch(address)
          super
        end

        def ppu_write(address, value)
          @a12_watcher.watch(address)
          super
        end

        def ppu_address(address)
          @a12_watcher.watch(address)
        end

        private

        # One `when` per register: the decoder is as wide as the register file.
        # rubocop:disable-next Metrics/CyclomaticComplexity
        def write_register(address, value)
          case register_number(address)
          when BANK_SELECT then select_bank_register(value)
          when BANK_DATA then load_bank_register(value)
          when MIRRORING then select_mirroring(value)
          when PRG_RAM_PROTECT then nil
          when IRQ_LATCH then @irq_counter.latch = value
          when IRQ_RELOAD then @irq_counter.request_reload
          when IRQ_DISABLE then @irq_counter.disable
          else @irq_counter.enable
          end
        end

        def register_number(address)
          pair = Bits.bit_field(address, mask: PAIR_SELECT_MASK, shift: PAIR_SELECT_SHIFT)
          (pair * REGISTERS_PER_PAIR) + ((address & ODD_ADDRESS_FLAG) == 0 ? 0 : 1) # glossary: flag-clear
        end

        def select_bank_register(value)
          @bank_select = value
          select_banks
        end

        def load_bank_register(value)
          @bank_registers[Bits.low_bits(@bank_select, BANK_REGISTER_MASK)] = value
          select_banks
        end

        def select_mirroring(value)
          return if @four_screen

          @mirroring = MIRRORINGS[Bits.low_bits(value, MIRRORING_FLAG)]
        end

        def select_banks
          select_prg_banks(PRG_LAYOUTS[(@bank_select & PRG_MODE_FLAG) == 0 ? 0 : 1]) # glossary: flag-clear
          select_chr_banks(CHR_LAYOUTS[(@bank_select & CHR_INVERSION_FLAG) == 0 ? 0 : 1]) # glossary: flag-clear
        end

        def select_prg_banks(layout)
          bank_count = last_prg_bank(PRG_BANK_SIZE) + 1
          layout.each_with_index do |source, window|
            bank = source.negative? ? bank_count + source : @bank_registers[source]
            select_prg_bank(PRG_ROM_START + (window * PRG_BANK_SIZE), bank, PRG_BANK_SIZE)
          end
        end

        # A 2 KiB register counts 1 KiB banks, so its bank number is the register halved: its low bit is ignored.
        def select_chr_banks(layout)
          layout.each_with_index do |(address, size), register|
            select_chr_bank(address, @bank_registers[register] / (size / ONE_KIB), size)
          end
        end
      end
    end
  end
end

require_relative 'mmc3/irq_counter'
require_relative 'mmc3/a12_watcher'
