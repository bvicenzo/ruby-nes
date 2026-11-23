# frozen_string_literal: true

module Ruby
  module Nes
    module Mappers
      # The cartridge board every mapper is built on (plan 19, decision 1). The CPU sees PRG ROM through four 8 KiB
      # windows, $8000, $A000, $C000 and $E000, and the PPU sees CHR through eight 1 KiB windows from $0000 (plan 21,
      # decision 8): MMC3's granularity (https://www.nesdev.org/wiki/MMC3), with which every other board's banks are a
      # whole number of windows (BankWindows). A board with registers only turns their writes into bank selections
      # (`write_register`). Out of the box $8000-$BFFF shows the first 16 KiB of PRG ROM and $C000-$FFFF the last 16
      # KiB, which is NROM-128 (both the same 16 KiB), NROM-256 and the fixed bank of UxROM
      # (https://www.nesdev.org/wiki/UxROM); CHR shows its first 8 KiB.
      #
      # PRG RAM at $6000-$7FFF is 8 KiB when the board says it has some (`prg_ram: true`), and a board may turn it off
      # (MMC1); without it, or off, the board does not drive the bus there. Nothing answers $4020-$5FFF. No CHR ROM
      # means 8 KiB of CHR RAM (iNES page: CHR ROM size 0 "means the board uses CHR RAM"). Mirroring is the header's
      # until a board changes it; flags 6 bit 3 asks for four-screen VRAM, whatever the mirroring bit says (plan 21,
      # decision 7), until a board that controls its mirroring (AxROM, MMC1) sets its own; MMC3 keeps it. Every board is
      # handed the CPU (`cpu=`: MMC1's clock, MMC3's IRQ line), the PPU (`ppu=`: MMC3's A12 clock) and the register sync
      # that catches the PPU up before a register write (`register_sync=`; plan 20 decision 1, plan 21 decisions 2 and
      # 6).
      class Base
        PRG_RAM_START = 0x6000
        PRG_ROM_START = 0x8000
        # $6000-$7FFF folds onto the 8 KiB of PRG RAM.
        PRG_RAM_MIRROR_MASK = 0x1FFF
        PRG_RAM_SIZE = 8_192
        PRG_WINDOW_SIZE = 8_192
        PRG_WINDOW_COUNT = 4
        # Address bits 14-13 tell the window: $8000-$9FFF is 0 … $E000-$FFFF is 3.
        PRG_WINDOW_SELECT_MASK = 0x6000
        PRG_WINDOW_SELECT_SHIFT = 13
        # The address bits within an 8 KiB window.
        PRG_WINDOW_OFFSET_MASK = 0x1FFF
        # $C000-$FFFF, the upper half of PRG ROM's 32 KiB; banks of 16 and 32 KiB.
        PRG_UPPER_HALF_START = 0xC000
        PRG_HALF_AREA_SIZE = 16_384
        PRG_AREA_SIZE = 32_768
        CHR_START = 0x0000
        CHR_RAM_SIZE = 8_192
        CHR_WINDOW_SIZE = 1_024
        CHR_WINDOW_COUNT = 8
        # Address bits 12-10 tell the window: $0000-$03FF is 0 … $1C00-$1FFF is 7.
        CHR_WINDOW_SELECT_MASK = 0x1C00
        CHR_WINDOW_SELECT_SHIFT = 10
        # The address bits within a 1 KiB window.
        CHR_WINDOW_OFFSET_MASK = 0x03FF
        # $1000-$1FFF, the upper half of the pattern tables; banks of 4 and 8 KiB.
        CHR_UPPER_HALF_START = 0x1000
        CHR_HALF_AREA_SIZE = 4_096
        CHR_AREA_SIZE = 8_192
        # The cycle of an IRQ that cannot come: later than any CPU cycle.
        NEVER = Float::INFINITY

        attr_reader :mirroring
        # The CPU, the board's clock (MMC1, plan 20 decision 1); the PPU, A12's clock (MMC3, plan 21 decision 2); the
        # Console::PpuRegisterSync that catches the PPU up before a register write (plan 21, decision 6).
        attr_writer :cpu, :ppu, :register_sync

        def initialize(cartridge, prg_ram: false)
          @prg_rom = cartridge.prg_rom
          @prg_windows = BankWindows.new(
            memory_size: @prg_rom.size,
            window_size: PRG_WINDOW_SIZE,
            window_count: PRG_WINDOW_COUNT,
            first_address: PRG_ROM_START
          )
          @prg_window_offsets = @prg_windows.offsets
          @prg_ram_enabled = prg_ram
          @prg_ram = prg_ram ? Array.new(PRG_RAM_SIZE, 0) : []
          @chr_writable = cartridge.chr_rom.empty?
          @chr = @chr_writable ? Array.new(CHR_RAM_SIZE, 0) : cartridge.chr_rom
          @chr_windows = BankWindows.new(
            memory_size: @chr.size,
            window_size: CHR_WINDOW_SIZE,
            window_count: CHR_WINDOW_COUNT,
            first_address: CHR_START
          )
          @chr_window_offsets = @chr_windows.offsets
          @mirroring = cartridge.header.alternative_nametables? ? :four_screen : cartridge.header.mirroring
          @cpu = nil
          @ppu = nil
          @register_sync = nil
          show_power_up_banks
        end

        # Returns what is left on the CPU data bus: a PRG ROM byte through its window, a PRG RAM byte, or `data_bus`
        # untouched where the board does not drive the bus. The CPU bus only hands addresses from $4020.
        def cpu_read(address, data_bus)
          if address >= PRG_ROM_START
            window = (address & PRG_WINDOW_SELECT_MASK) >> PRG_WINDOW_SELECT_SHIFT # glossary: bit-field
            @prg_rom[@prg_window_offsets[window] + (address & PRG_WINDOW_OFFSET_MASK)] # glossary: low-bits
          elsif address >= PRG_RAM_START && @prg_ram_enabled
            @prg_ram[address & PRG_RAM_MIRROR_MASK] # glossary: mirror-down
          else
            data_bus
          end
        end

        # $8000-$FFFF goes to the board's registers, once the PPU caught up with the write (without a register sync,
        # in specs, at once); $6000-$7FFF to PRG RAM when it is on; the rest is ignored.
        def cpu_write(address, value)
          if address >= PRG_ROM_START
            @register_sync&.catch_up
            write_register(address, value)
          elsif address >= PRG_RAM_START && @prg_ram_enabled
            @prg_ram[address & PRG_RAM_MIRROR_MASK] = value # glossary: mirror-down
          end
        end

        # The PPU bus only hands pattern table addresses, $0000-$1FFF.
        def ppu_read(address)
          window = (address & CHR_WINDOW_SELECT_MASK) >> CHR_WINDOW_SELECT_SHIFT # glossary: bit-field
          @chr[@chr_window_offsets[window] + (address & CHR_WINDOW_OFFSET_MASK)] # glossary: low-bits
        end

        # The PPU put `address` on its bus without reading or writing: v after a PPUADDR write or a PPUDATA increment,
        # outside rendering (plan 21, decision 10). Only a board that watches the bus (MMC3's A12) does anything with
        # it.
        def ppu_address(_address); end

        # The earliest CPU cycle on which the PPU's fetches could make the board assert its IRQ, the PPU standing on
        # `cycle`: the console catches the PPU up by then (plan 28, decision 3). A board without such an IRQ answers
        # NEVER.
        def earliest_irq_cycle(_cycle) = NEVER

        # CHR ROM ignores writes; CHR RAM keeps them.
        def ppu_write(address, value)
          return unless @chr_writable

          window = (address & CHR_WINDOW_SELECT_MASK) >> CHR_WINDOW_SELECT_SHIFT # glossary: bit-field
          @chr[@chr_window_offsets[window] + (address & CHR_WINDOW_OFFSET_MASK)] = value # glossary: low-bits
        end

        private

        # A board without registers ignores writes to $8000-$FFFF.
        def write_register(_address, _value); end

        # Shows the PRG ROM bank `bank`, counted in banks of `size` bytes (a whole number of 8 KiB windows), from
        # `address` on: `select_prg_bank(PRG_UPPER_HALF_START, 3, PRG_HALF_AREA_SIZE)` shows the fourth 16 KiB at
        # $C000-$FFFF. A bank past the end wraps around PRG ROM (BankWindows). Called on register writes, off the hot
        # path.
        def select_prg_bank(address, bank, size)
          @prg_windows.select(address, bank, size)
        end

        # The number of the last bank of `size` bytes of PRG ROM.
        def last_prg_bank(size) = @prg_windows.last_bank(size)

        # Shows the CHR bank `bank`, counted in banks of `size` bytes (a whole number of 1 KiB windows), from `address`
        # on, wrapped around the CHR size as select_prg_bank wraps PRG.
        def select_chr_bank(address, bank, size)
          @chr_windows.select(address, bank, size)
        end

        # Turns PRG RAM on or off (MMC1's PRG bank bit 4); only for a board built with `prg_ram: true`.
        def enable_prg_ram(enabled)
          @prg_ram_enabled = enabled
        end

        # The first and the last 16 KiB of PRG ROM, the first 8 KiB of CHR.
        def show_power_up_banks
          select_prg_bank(PRG_ROM_START, 0, PRG_HALF_AREA_SIZE)
          select_prg_bank(PRG_UPPER_HALF_START, last_prg_bank(PRG_HALF_AREA_SIZE), PRG_HALF_AREA_SIZE)
          select_chr_bank(CHR_START, 0, CHR_AREA_SIZE)
        end
      end
    end
  end
end
