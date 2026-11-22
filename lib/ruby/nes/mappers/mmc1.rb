# frozen_string_literal: true

module Ruby
  module Nes
    module Mappers
      # MMC1, iNES mapper 1 (https://www.nesdev.org/wiki/MMC1), the MMC1B revision ("Mapper 1 is used if the revision is
      # not known or irrelevant"). Writes to $8000-$FFFF reach a serial port (SerialPort): five writes load a 5-bit
      # value into the register "selected by bits 14 and 13 of the address" of the fifth, Control ($8000-$9FFF), CHR
      # bank 0 ($A000-$BFFF), CHR bank 1 ($C000-$DFFF) or PRG bank ($E000-$FFFF); a write with bit 7 set resets the port
      # and ORs Control with $0C. The port needs the CPU cycle of each write, so the board must be handed the CPU
      # (`cpu=`) before a register write (plan 20, decision 1).
      #
      # - Control `CPPMM`: MM the nametable arrangement (0 one-screen lower, 1 one-screen upper, 2 vertical, 3
      #   horizontal mirroring); PP the PRG mode (0 and 1 switch 32 KiB at $8000 ignoring the bank's low bit, 2 fixes
      #   the first bank at $8000, 3 fixes the last bank at $C000); C the CHR mode (0 one 8 KiB bank, 1 two 4 KiB).
      # - CHR bank 0: the 4 KiB bank at $0000, or the 8 KiB bank with its low bit ignored; CHR bank 1: the 4 KiB bank at
      #   $1000, ignored in 8 KiB mode.
      # - PRG bank: bits 3-0 the 16 KiB bank (low bit ignored in 32 KiB mode); bit 4 turns PRG RAM off on the MMC1B
      #   (plan 20, decision 6). PRG RAM is 8 KiB.
      # - SUROM: with 512 KiB of PRG ROM, CHR bank 0 bit 4 selects the 256 KiB outer bank, which "applies to all the PRG
      #   area, including the normally "fixed" bank" (plan 20, decision 7).
      #
      # Power-up: Control is $0C, as after a reset, the other registers 0 (plan 20, decision 4): the header's mirroring
      # is ignored. Banks are selected when a register is loaded, off the hot path.
      class Mmc1 < Base
        # "Writing a value with bit 7 set ($80 through $FF) to any address in $8000-$FFFF clears the shift register".
        RESET_FLAG = 0x80
        # What a reset ORs into Control: PRG mode 3.
        CONTROL_RESET_BITS = 0x0C
        # Address bits 14-13: the register the fifth write loads, numbered as @registers holds them.
        REGISTER_SELECT_MASK = 0x6000
        REGISTER_SELECT_SHIFT = 13
        CONTROL = 0
        CHR_BANK_0 = 1
        CHR_BANK_1 = 2
        PRG_BANK = 3
        # Control bits 1-0, the nametable arrangement, as the mirroring the PPU bus asks for.
        ARRANGEMENT_MASK = 0x03
        MIRRORINGS = %i[single_screen_lower single_screen_upper vertical horizontal].freeze
        # Control bits 3-2: the PRG mode; 0 and 1 are the 32 KiB mode.
        PRG_MODE_MASK = 0x0C
        PRG_MODE_SHIFT = 2
        FIX_FIRST_BANK_MODE = 2
        FIX_LAST_BANK_MODE = 3
        # Control bit 4: two 4 KiB CHR banks.
        TWO_CHR_BANKS_FLAG = 0x10
        # PRG bank bits 3-0 select a 16 KiB bank; bit 4 turns PRG RAM off.
        PRG_BANK_MASK = 0x0F
        PRG_RAM_OFF_FLAG = 0x10
        # SUROM: CHR bank 0 bit 4 selects which 256 KiB of a 512 KiB PRG ROM the windows see.
        OUTER_BANK_PRG_ROM_SIZE = 524_288
        OUTER_BANK_FLAG = 0x10
        # The 16 KiB banks in 256 KiB, the reach of bits 3-0; the last of them is the fixed bank of mode 3, or the last
        # bank of a smaller PRG ROM (plan 20, review).
        BANKS_PER_OUTER_BANK = 16
        LAST_INNER_BANK = 15
        # The 32 KiB PRG mode and the 8 KiB CHR mode select a bank twice as large as a register's unit.
        HALVES_PER_WHOLE_BANK = 2

        def initialize(cartridge)
          super(cartridge, prg_ram: true)
          @serial_port = SerialPort.new
          @outer_bank_wired = cartridge.prg_rom.size == OUTER_BANK_PRG_ROM_SIZE
          @registers = [CONTROL_RESET_BITS, 0, 0, 0]
          select_banks
        end

        private

        def write_register(address, value)
          cycle = @cpu.cycles
          if (value & RESET_FLAG) == 0 # glossary: flag-clear
            loaded = @serial_port.shift(value, cycle)
            return unless loaded

            @registers[Bits.bit_field(address, mask: REGISTER_SELECT_MASK, shift: REGISTER_SELECT_SHIFT)] = loaded
          else
            @serial_port.reset(cycle)
            @registers[CONTROL] = Bits.set_flag(@registers[CONTROL], CONTROL_RESET_BITS)
          end
          select_banks
        end

        # Turns the four registers into the mirroring, the windows and the PRG RAM switch.
        def select_banks
          control = @registers[CONTROL]
          @mirroring = MIRRORINGS[Bits.low_bits(control, ARRANGEMENT_MASK)]
          select_prg_banks(Bits.bit_field(control, mask: PRG_MODE_MASK, shift: PRG_MODE_SHIFT))
          select_chr_banks((control & TWO_CHR_BANKS_FLAG) != 0) # glossary: flag-set
          enable_prg_ram((@registers[PRG_BANK] & PRG_RAM_OFF_FLAG) == 0) # glossary: flag-clear
        end

        # Modes 0 and 1 show the 32 KiB bank holding the selected 16 KiB bank, its low bit ignored. Mode 3's fixed bank
        # is the last of the 256 KiB, or the last bank of a PRG ROM that is smaller and not a power of two (80 KiB
        # cpu_interrupts.nes), where bank 15 would wrap elsewhere.
        def select_prg_banks(mode)
          first_bank = first_bank_of_outer_bank
          bank = first_bank + Bits.low_bits(@registers[PRG_BANK], PRG_BANK_MASK)
          case mode
          when FIX_FIRST_BANK_MODE
            select_prg_bank(PRG_ROM_START, first_bank, PRG_HALF_AREA_SIZE)
            select_prg_bank(PRG_UPPER_HALF_START, bank, PRG_HALF_AREA_SIZE)
          when FIX_LAST_BANK_MODE
            select_prg_bank(PRG_ROM_START, bank, PRG_HALF_AREA_SIZE)
            select_prg_bank(PRG_UPPER_HALF_START, fixed_last_bank(first_bank), PRG_HALF_AREA_SIZE)
          else
            select_prg_bank(PRG_ROM_START, bank / HALVES_PER_WHOLE_BANK, PRG_AREA_SIZE)
          end
        end

        # Mode 3's fixed 16 KiB bank: the last of the 256 KiB from `first_bank`, or PRG ROM's last bank before it.
        def fixed_last_bank(first_bank) = [first_bank + LAST_INNER_BANK, last_prg_bank(PRG_HALF_AREA_SIZE)].min

        # The first 16 KiB bank of the 256 KiB the windows see: the second 256 KiB of a SUROM when CHR bank 0 bit 4
        # says so.
        def first_bank_of_outer_bank
          return 0 unless @outer_bank_wired && (@registers[CHR_BANK_0] & OUTER_BANK_FLAG) != 0 # glossary: flag-set

          BANKS_PER_OUTER_BANK
        end

        def select_chr_banks(two_banks)
          if two_banks
            select_chr_bank(CHR_START, @registers[CHR_BANK_0], CHR_HALF_AREA_SIZE)
            select_chr_bank(CHR_UPPER_HALF_START, @registers[CHR_BANK_1], CHR_HALF_AREA_SIZE)
          else
            select_chr_bank(CHR_START, @registers[CHR_BANK_0] / HALVES_PER_WHOLE_BANK, CHR_AREA_SIZE)
          end
        end
      end
    end
  end
end

require_relative 'mmc1/serial_port'
