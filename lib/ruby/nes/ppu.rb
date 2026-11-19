# frozen_string_literal: true

module Ruby
  module Nes
    # The 2C02 Picture Processing Unit as the CPU sees it (https://www.nesdev.org/wiki/PPU_registers): the eight
    # registers at $2000-$2007, plugged into CpuBus's `ppu_registers:` slot, which hands them already mirrored down.
    # Behind them, the scroll registers v/t/x/w, OAM and the PPUDATA port over the PPU bus.
    #
    # PPU open bus (https://www.nesdev.org/wiki/Open_bus_behavior#PPU_open_bus): the PPU keeps its own I/O latch,
    # modelled without decay (plan 11, decision 1). "Writes to any PPU port [...] load a value onto the PPU's I/O bus";
    # reads of $2004 and $2007 load the byte read; a PPUSTATUS read loads its bits 7-5 only; the write-only registers
    # and PPUSTATUS's bits 4-0 answer the latch. The CPU's data bus never reaches it, so `cpu_read` ignores `data_bus`.
    #
    # Time (plan 12): `catch_up` advances the frame timing 3 dots per CPU cycle
    # (https://www.nesdev.org/wiki/Cycle_reference_chart). The Ppu hears the frame timing's VBlank events and the VBlank
    # flag's /NMI output, and tells `nmi_input.nmi_line_changed(asserted, cycle)` with the first CPU cycle whose φ2
    # sample sees the change. `nmi_input` is given as a keyword or, by the Console, which builds the CPU after the PPU,
    # through its writer.
    #
    # Reset (https://www.nesdev.org/wiki/PPU_power_up_state): the reset signal clears PPUCTRL, PPUMASK, PPUSCROLL,
    # PPUADDR, their latch and the PPUDATA read buffer, and is "cleared at the end of VBlank"; until then writes to
    # PPUCTRL, PPUMASK, PPUSCROLL and PPUADDR have no effect; by convention they still load the I/O latch (plan 12,
    # decision 11).
    # `Ppu.new` is ready: writes are accepted until the first reset (plan 12, decision 8).
    #
    # Not yet: the sprite 0 hit and overflow flags (PPUSTATUS bits 6-5 read 0 until plan 14).
    class Ppu
      PPUCTRL = 0x2000
      PPUMASK = 0x2001
      PPUSTATUS = 0x2002
      OAMADDR = 0x2003
      OAMDATA = 0x2004
      PPUSCROLL = 0x2005
      PPUADDR = 0x2006
      PPUDATA = 0x2007

      # PPUCTRL bit 2: "VRAM address increment per CPU read/write of PPUDATA (0: add 1, going across; 1: add 32, going
      # down)".
      VRAM_INCREMENT_FLAG = 0x04
      ACROSS_INCREMENT = 1
      DOWN_INCREMENT = 32
      # PPUMASK bit 0: "Greyscale (0: normal color, 1: greyscale)".
      GREYSCALE_FLAG = 0x01
      # PPUCTRL bit 4: "Background pattern table address (0: $0000; 1: $1000)".
      BACKGROUND_PATTERN_TABLE_FLAG = 0x10
      FIRST_PATTERN_TABLE = 0x0000
      SECOND_PATTERN_TABLE = 0x1000
      # PPUCTRL bit 7: "Vblank NMI enable (0: off, 1: on)".
      NMI_ENABLE_FLAG = 0x80
      # PPUMASK bit 1: "Show background in leftmost 8 pixels of screen, 0: Hide"; bit 3: "Enable background rendering".
      LEFT_BACKGROUND_FLAG = 0x02
      BACKGROUND_FLAG = 0x08
      # PPUMASK bits 3-4: show the background, show the sprites; either one is "rendering" for the frame timing.
      RENDERING_FLAGS = 0x18
      # PPUSTATUS bits 4-0 are "PPU open bus"; bit 7 is the VBlank flag; sprite 0 hit and overflow (bits 6-5) read 0
      # until plan 14.
      STATUS_OPEN_BUS_BITS = 0x1F
      VERTICAL_BLANK_FLAG = 0x80
      # "3 dots per CPU cycle" on NTSC (https://www.nesdev.org/wiki/Cycle_reference_chart).
      DOTS_PER_CPU_CYCLE = 3
      # The CPU samples NMI "during φ2 of each CPU cycle" (https://www.nesdev.org/wiki/CPU_interrupts), before the
      # cycle's last dot: a change on that dot is seen in the next cycle. Calibrated with ppu_vbl_nmi 05-08 (plan 12,
      # decision 2).
      NMI_SAMPLE_LEAD_DOTS = 1

      attr_writer :nmi_input

      # One optional keyword per collaborator, so specs can observe or stand in for each.
      # rubocop:disable-next Metrics/ParameterLists
      def initialize(bus:, nmi_input: nil, scroll_registers: ScrollRegisters.new, oam: Oam.new,
                     frame_timing: FrameTiming.new(events: self), vertical_blank: VerticalBlank.new(nmi_output: self),
                     background_renderer: BackgroundRenderer.new(
                       scroll_registers:,
                       fetcher: BackgroundFetcher.new(bus:, scroll_registers:),
                       picture: Picture.new(bus:)
                     ))
        @nmi_input = nmi_input
        @scroll_registers = scroll_registers
        @oam = oam
        @frame_timing = frame_timing
        @vertical_blank = vertical_blank
        @background_renderer = background_renderer
        @data_port = DataPort.new(bus:, scroll_registers:, frame_timing:)
        @latch = 0
        @dots = 0
        @writes_ignored = false
      end

      def scanline = @frame_timing.scanline

      def dot = @frame_timing.dot

      def frame_number = @frame_timing.frame_number

      # The picture drawn so far, 256 × 240 palette indices row by row (docs/architecture.md, Frame buffer contract).
      def frame_buffer = @background_renderer.frame_buffer

      # Advances the PPU to the start of the given CPU cycle: 3 dots per cycle; a cycle already reached advances
      # nothing.
      def catch_up(cpu_cycle)
        target = cpu_cycle * DOTS_PER_CPU_CYCLE
        while @dots < target
          # The dot entered counts before the frame timing runs it, so its events carry that dot's CPU cycle.
          @dots += 1
          @frame_timing.advance
          @background_renderer.run_dot(@frame_timing.scanline, @frame_timing.dot)
        end
      end

      # The reset signal: clears PPUCTRL, PPUMASK, t, fine x, w and the PPUDATA read buffer, puts the frame timing at
      # the top of an even frame, and ignores the writes it guards until VBlank ends. v, OAMADDR and the VBlank flag
      # stay.
      def reset
        write_control(0)
        write_mask(0)
        @scroll_registers.reset
        @data_port.clear_read_buffer
        @frame_timing.reset
        @writes_ignored = true
      end

      def vertical_blank_started
        @vertical_blank.vertical_blank_started
      end

      # The end of VBlank also clears the reset signal.
      def vertical_blank_ended
        @vertical_blank.vertical_blank_ended
        @writes_ignored = false
      end

      # The VBlank flag's /NMI output changed on the dot the PPU stands on (the dot just entered when the change comes
      # from the frame timing, the next one to run between catch-ups): the CPU hears it with the first cycle whose φ2
      # sample sees that dot.
      def nmi_output_changed(asserted)
        @nmi_input.nmi_line_changed(asserted, (@dots + NMI_SAMPLE_LEAD_DOTS) / DOTS_PER_CPU_CYCLE)
      end

      # The byte the register puts on the CPU data bus; `data_bus` is not read (the PPU answers from its own latch).
      def cpu_read(address, _data_bus)
        case address
        when PPUSTATUS then read_status
        when OAMDATA then @latch = @oam.read
        when PPUDATA then @latch = @data_port.read(@latch)
        else @latch
        end
      end

      # One `when` per writable register: the decoder is as wide as the register file.
      # rubocop:disable-next Metrics/CyclomaticComplexity
      def cpu_write(address, value)
        @latch = value
        case address
        when PPUCTRL then write_control(value) unless @writes_ignored
        when PPUMASK then write_mask(value) unless @writes_ignored
        when OAMADDR then @oam.address = value
        when OAMDATA then @oam.write(value)
        when PPUSCROLL then @scroll_registers.write_scroll(value) unless @writes_ignored
        when PPUADDR then @scroll_registers.write_address(value) unless @writes_ignored
        when PPUDATA then @data_port.write(value)
        end
      end

      private

      # "Reading this register has the side effect of clearing the PPU's internal w register"; it also clears the VBlank
      # flag, and the frame timing hears of it for the read race.
      def read_status
        @scroll_registers.reset_write_toggle
        @frame_timing.status_read
        flags = @vertical_blank.read ? VERTICAL_BLANK_FLAG : 0
        @latch = flags | (@latch & STATUS_OPEN_BUS_BITS) # glossary: bitwise-or, low-bits
      end

      def write_control(value)
        @scroll_registers.write_control(value)
        @data_port.increment = value.anybits?(VRAM_INCREMENT_FLAG) ? DOWN_INCREMENT : ACROSS_INCREMENT
        @vertical_blank.nmi_enabled = value.anybits?(NMI_ENABLE_FLAG)
        second_table = value.anybits?(BACKGROUND_PATTERN_TABLE_FLAG)
        @background_renderer.pattern_table = second_table ? SECOND_PATTERN_TABLE : FIRST_PATTERN_TABLE
      end

      def write_mask(value)
        greyscale = value.anybits?(GREYSCALE_FLAG)
        rendering_enabled = value.anybits?(RENDERING_FLAGS)
        @data_port.greyscale = greyscale
        @background_renderer.greyscale = greyscale
        @background_renderer.left_columns_shown = value.anybits?(LEFT_BACKGROUND_FLAG)
        @background_renderer.background_enabled = value.anybits?(BACKGROUND_FLAG)
        @frame_timing.rendering_enabled = rendering_enabled
        @background_renderer.rendering_enabled = rendering_enabled
      end
    end
  end
end

require_relative 'ppu/scroll_registers'
require_relative 'ppu/oam'
require_relative 'ppu/data_port'
require_relative 'ppu/frame_timing'
require_relative 'ppu/vertical_blank'
require_relative 'ppu/background_fetcher'
require_relative 'ppu/background_shifters'
require_relative 'ppu/picture'
require_relative 'ppu/background_visibility'
require_relative 'ppu/background_schedule'
require_relative 'ppu/background_renderer'
