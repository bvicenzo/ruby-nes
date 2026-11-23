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
    # (https://www.nesdev.org/wiki/Cycle_reference_chart), in ranges within a scanline up to the frame timing's last
    # quiet dot, each run by the renderer with the dot clock on its first dot (plan 28, decisions 4 and 5). `sync_cycle`
    # tells the console when it must next catch the PPU up for the CPU to see it on time (decision 2). The Ppu hears the
    # frame timing's VBlank events and the VBlank flag's /NMI output, and tells `nmi_input.nmi_line_changed(asserted,
    # cycle)` with the first CPU cycle whose φ2 sample sees the change. `nmi_input` is given as a keyword or, by the
    # Console, which builds the CPU after the PPU, through its writer.
    #
    # Reset (https://www.nesdev.org/wiki/PPU_power_up_state): the reset signal clears PPUCTRL, PPUMASK, PPUSCROLL,
    # PPUADDR, their latch and the PPUDATA read buffer, and is "cleared at the end of VBlank"; until then writes to
    # PPUCTRL, PPUMASK, PPUSCROLL and PPUADDR have no effect; by convention they still load the I/O latch (plan 12,
    # decision 11).
    # `Ppu.new` is ready: writes are accepted until the first reset (plan 12, decision 8).
    #
    # OAMDATA writes "during rendering [...] do not modify values in OAM, but do perform a glitchy increment of OAMADDR";
    # as NESdev advises for emulators, they are ignored completely (plan 14, decision 4) and only load the latch.
    #
    # Rendering (plans 13 and 14): the Renderer runs each dot's work, the SpriteRenderer its sprite part; the Ppu decodes
    # PPUCTRL and PPUMASK and tells each the settings it uses. PPUSTATUS bits 6-5 are the SpriteStatus's.
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
      # PPUCTRL bit 3: "Sprite pattern table address for 8x8 sprites (0: $0000; 1: $1000; ignored in 8x16 mode)"; bit 5:
      # "Sprite size (0: 8x8 pixels; 1: 8x16 pixels)".
      SPRITE_PATTERN_TABLE_FLAG = 0x08
      SPRITE_SIZE_FLAG = 0x20
      # PPUCTRL bit 7: "Vblank NMI enable (0: off, 1: on)".
      NMI_ENABLE_FLAG = 0x80
      # PPUMASK bit 1: "Show background in leftmost 8 pixels of screen, 0: Hide"; bit 3: "Enable background rendering".
      LEFT_BACKGROUND_FLAG = 0x02
      BACKGROUND_FLAG = 0x08
      # PPUMASK bit 2: "Show sprites in leftmost 8 pixels of screen, 0: Hide"; bit 4: "Enable sprite rendering".
      LEFT_SPRITES_FLAG = 0x04
      SPRITES_FLAG = 0x10
      # PPUMASK bits 3-4: show the background, show the sprites; either one is "rendering" for the frame timing.
      RENDERING_FLAGS = 0x18
      # PPUMASK bits 5-7: "Emphasize red", "Emphasize green", "Emphasize blue" on NTSC
      # (https://www.nesdev.org/wiki/Colour_emphasis); the picture puts them in every pixel (plan 16, decision 2).
      EMPHASIS_FLAGS = 0xE0
      # PPUSTATUS bits 4-0 are "PPU open bus"; bit 7 is the VBlank flag; bits 6-5, sprite 0 hit and overflow, come from
      # the SpriteStatus.
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
                     sprite_status: SpriteStatus.new, clock: DotClock.new,
                     sprite_renderer: SpriteRenderer.build(bus:, oam:, status: sprite_status),
                     renderer: Renderer.new(
                       scroll_registers:,
                       fetcher: BackgroundFetcher.new(bus:, scroll_registers:),
                       picture: Picture.new(palette_ram: bus.palette_ram),
                       sprite_renderer:,
                       multiplexer: PriorityMultiplexer.new(sprite_zero_hit: SpriteZeroHit.new(status: sprite_status)),
                       clock:
                     ))
        @bus = bus
        @nmi_input = nmi_input
        @scroll_registers = scroll_registers
        @oam = oam
        @frame_timing = frame_timing
        @vertical_blank = vertical_blank
        @sprite_status = sprite_status
        @sprite_renderer = sprite_renderer
        @renderer = renderer
        @data_port = DataPort.new(bus:, scroll_registers:, frame_timing:)
        @clock = clock
        @latch = 0
        @writes_ignored = false
        @sync_cycle = nil
      end

      # The dots run since the PPU was built: a clock that never wraps, which MMC3's A12 filter reads (plan 21,
      # decision 2); within a range, the dot the renderer is on (plan 28, decision 5).
      def elapsed_dots = @clock.elapsed_dots

      def scanline = @frame_timing.scanline

      def dot = @frame_timing.dot

      def frame_number = @frame_timing.frame_number

      # The last complete frame, 256 × 240 pixels row by row (docs/architecture.md, Frame buffer contract). One of two
      # buffers the picture swaps: valid until the next frame completes, then drawn over; copy it to keep it.
      def frame_buffer = @renderer.frame_buffer

      # Advances the PPU to the start of the given CPU cycle: 3 dots per cycle; a cycle already reached advances
      # nothing. Each range enters its first dot through the frame timing, which tells its events, then runs up to the
      # frame timing's last quiet dot or the target (plan 28, decision 4).
      def catch_up(cpu_cycle)
        @sync_cycle = nil
        target = cpu_cycle * DOTS_PER_CPU_CYCLE
        while @clock.elapsed_dots < target
          # The dot entered counts before the frame timing runs it, so its events carry that dot's CPU cycle.
          @clock.tick
          @frame_timing.advance
          run_range(target)
        end
      end

      # The first CPU cycle at whose end the PPU must be caught up for the CPU to see on time what it changes: the
      # cycle of the frame timing's next event, /NMI or a new frame, or the board's earliest IRQ, whichever comes
      # first (plan 28, decision 2). An event on dot D changes /NMI on cycle (D + 1) / 3, which a step polls only if it
      # starts after it, so D / 3 is soon enough. Kept until a catch-up, a register access or a reset.
      def sync_cycle
        @sync_cycle ||= next_sync_cycle
      end

      # The reset signal: clears PPUCTRL, PPUMASK, t, fine x, w and the PPUDATA read buffer, puts the frame timing at
      # the top of an even frame, and ignores the writes it guards until VBlank ends. v, OAMADDR and the VBlank flag
      # stay.
      def reset
        @sync_cycle = nil
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

      # The frame timing entered the post-render scanline: the last visible pixel is drawn (plan 16, decision 1).
      def picture_completed
        @renderer.complete_picture
      end

      # The end of VBlank, dot 1 of the pre-render scanline, also clears the reset signal and the sprite flags, which
      # "are automatically cleared on dot 1 of the prerender scanline".
      def vertical_blank_ended
        @vertical_blank.vertical_blank_ended
        @sprite_status.clear
        @writes_ignored = false
      end

      # The VBlank flag's /NMI output changed on the dot the PPU stands on (the dot just entered when the change comes
      # from the frame timing, the next one to run between catch-ups): the CPU hears it with the first cycle whose φ2
      # sample sees that dot.
      def nmi_output_changed(asserted)
        @nmi_input.nmi_line_changed(asserted, (@clock.elapsed_dots + NMI_SAMPLE_LEAD_DOTS) / DOTS_PER_CPU_CYCLE)
      end

      # The byte the register puts on the CPU data bus; `data_bus` is not read (the PPU answers from its own latch).
      def cpu_read(address, _data_bus)
        @sync_cycle = nil
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
        @sync_cycle = nil
        @latch = value
        case address
        when PPUCTRL then write_control(value) unless @writes_ignored
        when PPUMASK then write_mask(value) unless @writes_ignored
        when OAMADDR then @oam.address = value
        when OAMDATA then @oam.write(value) unless @frame_timing.rendering_in_progress?
        when PPUSCROLL then @scroll_registers.write_scroll(value) unless @writes_ignored
        when PPUADDR then write_address(value) unless @writes_ignored
        when PPUDATA then @data_port.write(value)
        end
      end

      private

      # The renderer runs the dots from the one just entered, its count on the clock, to the frame timing's last quiet
      # dot or the target; the renderer may move the clock within the range, which ends on the range's last dot.
      def run_range(target)
        first_dot = @frame_timing.dot
        first_elapsed_dots = @clock.elapsed_dots
        last_dot = first_dot + target - first_elapsed_dots
        quiet_dot = @frame_timing.last_quiet_dot
        last_dot = quiet_dot if quiet_dot < last_dot
        @renderer.run_dots(@frame_timing.scanline, first_dot, last_dot)
        @frame_timing.advance_to(last_dot)
        @clock.elapsed_dots = first_elapsed_dots + last_dot - first_dot
      end

      def next_sync_cycle
        elapsed_dots = @clock.elapsed_dots
        event_cycle = (elapsed_dots + @frame_timing.dots_to_next_event) / DOTS_PER_CPU_CYCLE
        irq_cycle = @bus.earliest_irq_cycle(elapsed_dots / DOTS_PER_CPU_CYCLE)
        [event_cycle, irq_cycle].min
      end

      # "Reading this register has the side effect of clearing the PPU's internal w register"; it also clears the VBlank
      # flag, and the frame timing hears of it for the read race.
      def read_status
        @scroll_registers.reset_write_toggle
        @frame_timing.status_read
        flags = (@vertical_blank.read ? VERTICAL_BLANK_FLAG : 0) | @sprite_status.bits # glossary: bitwise-or
        @latch = flags | (@latch & STATUS_OPEN_BUS_BITS) # glossary: bitwise-or, low-bits
      end

      # PPUADDR: the first write fills t's high byte, the second loads v from t. Outside rendering the PPU's bus shows v
      # after either (DataPort#show_address); after the first it is unchanged, so only the second can raise A12.
      def write_address(value)
        @scroll_registers.write_address(value)
        @data_port.show_address
      end

      def write_control(value)
        @scroll_registers.write_control(value)
        going_down = (value & VRAM_INCREMENT_FLAG) != 0 # glossary: flag-set
        @data_port.increment = going_down ? DOWN_INCREMENT : ACROSS_INCREMENT
        @vertical_blank.nmi_enabled = (value & NMI_ENABLE_FLAG) != 0 # glossary: flag-set
        second_table = (value & BACKGROUND_PATTERN_TABLE_FLAG) != 0 # glossary: flag-set
        @renderer.pattern_table = second_table ? SECOND_PATTERN_TABLE : FIRST_PATTERN_TABLE
        write_sprite_control(value)
      end

      def write_sprite_control(value)
        second_table = (value & SPRITE_PATTERN_TABLE_FLAG) != 0 # glossary: flag-set
        @sprite_renderer.pattern_table = second_table ? SECOND_PATTERN_TABLE : FIRST_PATTERN_TABLE
        @sprite_renderer.tall_sprites = (value & SPRITE_SIZE_FLAG) != 0 # glossary: flag-set
      end

      def write_mask(value)
        greyscale = (value & GREYSCALE_FLAG) != 0 # glossary: flag-set
        rendering_enabled = (value & RENDERING_FLAGS) != 0 # glossary: flag-set
        @data_port.greyscale = greyscale
        @renderer.greyscale = greyscale
        @renderer.emphasis = value & EMPHASIS_FLAGS # glossary: bitwise-and
        @renderer.background_left_columns_shown = (value & LEFT_BACKGROUND_FLAG) != 0 # glossary: flag-set
        @renderer.background_enabled = (value & BACKGROUND_FLAG) != 0 # glossary: flag-set
        @renderer.sprite_left_columns_shown = (value & LEFT_SPRITES_FLAG) != 0 # glossary: flag-set
        @renderer.sprites_enabled = (value & SPRITES_FLAG) != 0 # glossary: flag-set
        @frame_timing.rendering_enabled = rendering_enabled
        @renderer.rendering_enabled = rendering_enabled
      end
    end
  end
end

require_relative 'ppu/scroll_registers'
require_relative 'ppu/oam'
require_relative 'ppu/sprite_rows'
require_relative 'ppu/overflow_search'
require_relative 'ppu/secondary_oam'
require_relative 'ppu/sprite_status'
require_relative 'ppu/sprite_pattern_address'
require_relative 'ppu/sprite_evaluation'
require_relative 'ppu/data_port'
require_relative 'ppu/frame_timing'
require_relative 'ppu/dot_clock'
require_relative 'ppu/vertical_blank'
require_relative 'ppu/background_fetcher'
require_relative 'ppu/picture'
require_relative 'ppu/sprite_line'
require_relative 'ppu/sprite_fetcher'
require_relative 'ppu/sprite_zero_hit'
require_relative 'ppu/priority_multiplexer'
require_relative 'ppu/layer_visibility'
require_relative 'ppu/render_schedule'
require_relative 'ppu/sprite_renderer'
require_relative 'ppu/pixel_composer'
require_relative 'ppu/renderer'
