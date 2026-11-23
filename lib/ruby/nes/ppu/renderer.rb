# frozen_string_literal: true

module Ruby
  module Nes
    class Ppu
      # Runs the rendering work of each dot as one pipeline (plans 13 and 14; plan 25, decision 7): the schedule gives
      # the steps, in order. The renderer owns the background's shift registers
      # (https://www.nesdev.org/wiki/PPU_rendering): 16 bits each, two of pattern and two of attribute; a reload puts
      # the fetched tile's pattern bytes, and its palette's two bits each repeated 8 times, in the low byte, behind the
      # tile on screen, before the dot's pixel; the registers shift left one bit after it. The pixel goes to x = dot − 1
      # of the scanline (plan 13, decision 5): the background's is the 4 bits at bit 15 − fine X, transparent when its
      # pattern value is 0; each layer shows from its first visible column on (LayerVisibility, PPUMASK bits 1-4); the
      # sprites' comes from the sprite renderer's line entries; the pixel composer draws the two (plan 30, decision 6).
      # The sprite steps go to the sprite renderer. The Ppu tells it the background's PPUCTRL settings and the PPUMASK
      # settings; it passes each to the part that uses it. The background's pixel is taken here, with the registers as
      # instance variables, rather than through one object per stage: a method call costs about 5 ns under YJIT, and the
      # stages cost about a third of a frame (plan 25).
      #
      # Ranges (plan 28): `run_dots` runs a range of a scanline's dots, the dot clock standing on the first one. A tile
      # of a visible line whose 8 dots the range covers runs as one unrolled sequence (RenderSchedule::WHOLE_TILE,
      # decision 6), and so do a visible line's sprite slots and the next line's two tiles (WHOLE_SLOT and
      # WHOLE_NEXT_LINE_TILE, plan 31); other dots run one at a time. The clock is moved to each dot's count before its
      # fetches, which the board's A12 watch reads (decision 5). Hot path: one `run_dots` per range, one step lookup
      # per dot or sequence.
      #
      # Past RuboCop's class length on purpose (plan 31): the background's pixel, its registers and the sequences of 8
      # dots stay inline in one object, where YJIT calls them through self (plan 25).
      class Renderer # rubocop:disable Metrics/ClassLength
        WIDTH = Picture::WIDTH
        FIRST_PIXEL_BIT = 15
        TILE_ON_SCREEN_MASK = 0xFF00
        SHIFT_REGISTER_MASK = Bits::WORD_MASK
        # A palette bit repeated over the 8 pixels of a tile.
        ATTRIBUTE_BYTE = [0x00, 0xFF].freeze
        PALETTE_HIGH_BIT_SHIFT = 1
        # Where each register's bit goes in the 4-bit pixel: palette high, palette low, pattern high, pattern low.
        PALETTE_HIGH_SHIFT = 3
        PALETTE_LOW_SHIFT = 2
        PATTERN_HIGH_SHIFT = 1
        # A pixel whose pattern value (bits 1-0) is 0 is transparent (https://www.nesdev.org/wiki/PPU_palettes).
        TRANSPARENT = 0
        # A whole tile's last dot, from its first, and the dots of its fetches (RenderSchedule::TILE_STEPS).
        TILE_LAST_DOT = RenderSchedule::TILE_DOTS - 1
        # The last dot of a sequence a WHOLE_STEPS flag starts, from its first.
        SEQUENCE_LAST_DOT = RenderSchedule::SEQUENCE_DOTS - 1
        NAMETABLE_DOT = RenderSchedule::TILE_STEPS.index(RenderSchedule::FETCH_NAMETABLE)
        ATTRIBUTE_DOT = RenderSchedule::TILE_STEPS.index(RenderSchedule::FETCH_ATTRIBUTE)
        PATTERN_LOW_DOT = RenderSchedule::TILE_STEPS.index(RenderSchedule::FETCH_PATTERN_LOW)
        PATTERN_HIGH_DOT = RenderSchedule::TILE_STEPS.index(RenderSchedule::FETCH_PATTERN_HIGH)

        # A whole tile's pixels (plan 30, decisions 2, 6 and 7). After the tile's reload, its pixel i (0-7) is bit 15 −
        # fine X − i of each register: the byte (register × 2^fine X) >> 8, bit 7 the leftmost pixel. A load-time table
        # per register spreads that byte one bit per nibble, in the register's place in the 4-bit pixel, pixel i in
        # bits 31 − 4i to 28 − 4i: the tile is the OR of the four, 8 pixels in 32 bits. Fine X picks a factor instead of
        # being a shift amount, because YJIT compiles a shift by a varying amount as a method call.
        TILE_PIXELS = RenderSchedule::TILE_DOTS
        PIXEL_BITS = 4
        WINDOW_SHIFT = 8
        WINDOW_MASK = Bits::BYTE_MASK
        FINE_X_FACTORS = Array.new(TILE_PIXELS) { 1 << it }.freeze # glossary: shift-left
        LEFTMOST_PIXEL_BIT = TILE_PIXELS - 1
        # A slot's first dot with nothing to run but the slot itself: every one but 257's (plan 31, decision 3).
        SLOT_ONLY_STEPS = RenderSchedule::WHOLE_SLOT | RenderSchedule::RESET_OAM_ADDRESS # glossary: bitwise-or
        # The columns of each of the sprite line's occupied tile flags.
        OCCUPIED_TILE_WIDTH = SpriteLine::TILE_WIDTH

        # The byte's bits spread over the nibbles of a tile, each at `place` within its nibble.
        def self.spread(byte, place)
          (0...TILE_PIXELS).sum do |column|
            nibble_shift = ((LEFTMOST_PIXEL_BIT - column) * PIXEL_BITS) + place
            Bits.bit_at(byte, LEFTMOST_PIXEL_BIT - column) << nibble_shift # glossary: shift-left
          end
        end
        private_class_method :spread

        PATTERN_LOW_PIXELS = Array.new(WINDOW_MASK + 1) { spread(it, 0) }.freeze
        PATTERN_HIGH_PIXELS = Array.new(WINDOW_MASK + 1) { spread(it, PATTERN_HIGH_SHIFT) }.freeze
        PALETTE_LOW_PIXELS = Array.new(WINDOW_MASK + 1) { spread(it, PALETTE_LOW_SHIFT) }.freeze
        PALETTE_HIGH_PIXELS = Array.new(WINDOW_MASK + 1) { spread(it, PALETTE_HIGH_SHIFT) }.freeze

        # One optional keyword per part, so specs can stand in for each.
        # rubocop:disable-next Metrics/ParameterLists
        def initialize(scroll_registers:, fetcher:, picture:, sprite_renderer:, multiplexer:,
                       schedule: RenderSchedule.new, background_visibility: LayerVisibility.new,
                       sprite_visibility: LayerVisibility.new, clock: DotClock.new)
          @scroll_registers = scroll_registers
          @fetcher = fetcher
          @picture = picture
          @sprite_renderer = sprite_renderer
          @sprite_entries = sprite_renderer.line_entries
          @occupied_tiles = sprite_renderer.occupied_tiles
          @schedule = schedule
          @background_visibility = background_visibility
          @sprite_visibility = sprite_visibility
          @clock = clock
          @composer = PixelComposer.new(picture:, sprite_entries: @sprite_entries, multiplexer:)
          @pattern_low = 0
          @pattern_high = 0
          @attribute_low = 0
          @attribute_high = 0
        end

        def frame_buffer = @picture.frame_buffer

        def pattern_table=(address)
          @fetcher.pattern_table = address
        end

        def greyscale=(enabled)
          @picture.greyscale = enabled
        end

        # PPUMASK's emphasis bits, 5-7, in place.
        def emphasis=(flags)
          @picture.emphasis = flags
        end

        # The PPU entered the post-render scanline: the frame drawn becomes the frame buffer (plan 16, decision 1), and
        # the next frame is drawn into the picture's other buffer.
        def complete_picture
          @composer.complete_picture
        end

        def background_enabled=(enabled)
          @background_visibility.enabled = enabled
        end

        def background_left_columns_shown=(shown)
          @background_visibility.left_columns_shown = shown
        end

        def sprites_enabled=(enabled)
          @sprite_visibility.enabled = enabled
        end

        def sprite_left_columns_shown=(shown)
          @sprite_visibility.left_columns_shown = shown
        end

        def rendering_enabled=(enabled)
          @schedule.rendering_enabled = enabled
        end

        # Runs dots `first_dot` to `last_dot` of the scanline, the clock standing on `first_dot`'s count.
        def run_dots(scanline, first_dot, last_dot)
          line = @schedule.line(scanline)
          line_elapsed_dots = @clock.elapsed_dots - first_dot
          dot = first_dot
          while dot <= last_dot
            steps = line[dot]
            if (steps & RenderSchedule::WHOLE_STEPS) != 0 && dot + SEQUENCE_LAST_DOT <= last_dot # glossary: flag-set
              run_whole_sequence(line, steps, scanline, dot, line_elapsed_dots + dot)
              dot += RenderSchedule::SEQUENCE_DOTS
            else
              run_dot(steps, scanline, dot, line_elapsed_dots + dot) unless steps.zero?
              dot += 1
            end
          end
        end

        private

        def run_dot(steps, scanline, dot, elapsed_dots)
          @clock.elapsed_dots = elapsed_dots
          output_pixel(steps, scanline, dot)
          fetch(steps)
          update_vram_address(steps)
          return if (steps & RenderSchedule::SPRITE_STEPS) == 0 # glossary: flag-clear

          @sprite_renderer.run_steps(steps, scanline, dot)
        end

        # The 8 dots from `dot`, whose count is `elapsed_dots`, as one sequence: a tile, a sprite slot (its dot's own
        # steps first where it has more than the slot's) or one of the next line's tiles.
        def run_whole_sequence(line, steps, scanline, dot, elapsed_dots)
          if (steps & RenderSchedule::WHOLE_TILE) != 0 # glossary: flag-set
            run_tile(line, scanline, dot, elapsed_dots)
          elsif (steps & RenderSchedule::WHOLE_SLOT) != 0 # glossary: flag-set
            run_dot(steps, scanline, dot, elapsed_dots) if steps != SLOT_ONLY_STEPS
            @sprite_renderer.run_slot(scanline, dot, elapsed_dots)
          else
            run_next_line_tile(steps, elapsed_dots)
          end
        end

        # The 8 dots of a visible line's tile from its first, `dot`, whose count is `elapsed_dots`: its 8 pixels at
        # x = dot − 1 onwards from the window under fine X, then the 8 shifts at once, since nothing reloads within the
        # tile; the tile's fetches (the clock on each one's dot), coarse X and Y follow RenderSchedule's steps for them,
        # the same as dot by dot; the reload and Y come from the line. A layer's first visible column is 0, 8 or 256, so
        # each layer shows in the whole tile or in none of it (plan 30, decision 6); a tile the sprite line flags clear
        # holds no sprite pixel, so it is the background alone too (plan 31, decision 1). Unrolled, without a step
        # lookup or a call per dot (plan 28, decision 6).
        # rubocop:disable-next Metrics/AbcSize
        def run_tile(line, scanline, dot, elapsed_dots)
          reload if (line[dot] & RenderSchedule::RELOAD) != 0 # glossary: flag-set
          x_position = dot - 1
          pixels = x_position < @background_visibility.first_visible_column ? TRANSPARENT : background_window
          if x_position < @sprite_visibility.first_visible_column || !@occupied_tiles[x_position / OCCUPIED_TILE_WIDTH]
            @composer.draw_background_tile(pixels, (scanline * WIDTH) + x_position)
          else
            @composer.draw_tile(pixels, x_position, (scanline * WIDTH) + x_position)
          end
          shift_tile
          fetch_tile(elapsed_dots)
          last_steps = line[dot + TILE_LAST_DOT]
          @scroll_registers.increment_y if (last_steps & RenderSchedule::INCREMENT_Y) != 0 # glossary: flag-set
        end

        # One of the next line's two tiles, from its first dot (plan 31, decision 5): the reload where the dot has one,
        # the 8 shifts at once, the fetches and coarse X, as a whole tile without its pixels.
        def run_next_line_tile(steps, elapsed_dots)
          reload if (steps & RenderSchedule::RELOAD) != 0 # glossary: flag-set
          shift_tile
          fetch_tile(elapsed_dots)
        end

        # A whole tile's four fetches, the clock on each one's dot, then coarse X on its last dot.
        def fetch_tile(elapsed_dots)
          @clock.elapsed_dots = elapsed_dots + NAMETABLE_DOT
          @fetcher.fetch_nametable_byte
          @clock.elapsed_dots = elapsed_dots + ATTRIBUTE_DOT
          @fetcher.fetch_attribute
          @clock.elapsed_dots = elapsed_dots + PATTERN_LOW_DOT
          @fetcher.fetch_pattern_low
          @clock.elapsed_dots = elapsed_dots + PATTERN_HIGH_DOT
          @fetcher.fetch_pattern_high
          @scroll_registers.increment_coarse_x
        end

        # The tile's 8 background pixels of 4 bits, transparent ones 0: the palette bits only where the pattern is
        # opaque.
        # rubocop:disable-next Metrics/AbcSize
        def background_window
          factor = FINE_X_FACTORS[@scroll_registers.fine_x]
          pattern_low = ((@pattern_low * factor) >> WINDOW_SHIFT) & WINDOW_MASK # glossary: bit-field
          pattern_high = ((@pattern_high * factor) >> WINDOW_SHIFT) & WINDOW_MASK # glossary: bit-field
          opaque = pattern_low | pattern_high # glossary: bitwise-or
          palette_low = ((@attribute_low * factor) >> WINDOW_SHIFT) & opaque # glossary: bit-field, bitwise-and
          palette_high = ((@attribute_high * factor) >> WINDOW_SHIFT) & opaque # glossary: bit-field, bitwise-and
          patterns = PATTERN_LOW_PIXELS[pattern_low] | PATTERN_HIGH_PIXELS[pattern_high] # glossary: bitwise-or
          patterns | PALETTE_LOW_PIXELS[palette_low] | PALETTE_HIGH_PIXELS[palette_high] # glossary: bitwise-or
        end

        # The 8 shifts of a whole tile at once (plan 30, decision 2).
        def shift_tile
          @pattern_low = (@pattern_low << TILE_PIXELS) & SHIFT_REGISTER_MASK # glossary: shift-left, low-bits
          @pattern_high = (@pattern_high << TILE_PIXELS) & SHIFT_REGISTER_MASK # glossary: shift-left, low-bits
          @attribute_low = (@attribute_low << TILE_PIXELS) & SHIFT_REGISTER_MASK # glossary: shift-left, low-bits
          @attribute_high = (@attribute_high << TILE_PIXELS) & SHIFT_REGISTER_MASK # glossary: shift-left, low-bits
        end

        def output_pixel(steps, scanline, dot)
          reload if (steps & RenderSchedule::RELOAD) != 0 # glossary: flag-set
          draw(scanline, dot - 1) if (steps & RenderSchedule::PIXEL) != 0 # glossary: flag-set
          if (steps & RenderSchedule::FORCED_BLANK_PIXEL) != 0 # glossary: flag-set
            @picture.draw_forced_blank(dot - 1, scanline, @scroll_registers.vram_address)
          end
          shift if (steps & RenderSchedule::SHIFT) != 0 # glossary: flag-set
        end

        def reload
          @pattern_low = (@pattern_low & TILE_ON_SCREEN_MASK) | @fetcher.pattern_low # glossary: place-bit-field
          @pattern_high = (@pattern_high & TILE_ON_SCREEN_MASK) | @fetcher.pattern_high # glossary: place-bit-field
          palette = @fetcher.palette
          attribute_low = ATTRIBUTE_BYTE[palette & 1] # glossary: bit-at
          attribute_high = ATTRIBUTE_BYTE[palette >> PALETTE_HIGH_BIT_SHIFT] # glossary: bit-at
          @attribute_low = (@attribute_low & TILE_ON_SCREEN_MASK) | attribute_low # glossary: place-bit-field
          @attribute_high = (@attribute_high & TILE_ON_SCREEN_MASK) | attribute_high # glossary: place-bit-field
        end

        def shift
          @pattern_low = (@pattern_low << 1) & SHIFT_REGISTER_MASK # glossary: shift-left, low-bits
          @pattern_high = (@pattern_high << 1) & SHIFT_REGISTER_MASK # glossary: shift-left, low-bits
          @attribute_low = (@attribute_low << 1) & SHIFT_REGISTER_MASK # glossary: shift-left, low-bits
          @attribute_high = (@attribute_high << 1) & SHIFT_REGISTER_MASK # glossary: shift-left, low-bits
        end

        # The background's 4 bits under fine X (0 when transparent or hidden) and the sprite line's entry at x (0 when
        # hidden), handed to the pixel composer.
        # rubocop:disable-next Metrics/AbcSize
        def draw(scanline, x_position)
          bit = FIRST_PIXEL_BIT - @scroll_registers.fine_x
          pattern_high = ((@pattern_high >> bit) & 1) << PATTERN_HIGH_SHIFT # glossary: bit-at, place-bit-field
          pattern = pattern_high | ((@pattern_low >> bit) & 1) # glossary: bitwise-or, bit-at
          background =
            if pattern == TRANSPARENT || x_position < @background_visibility.first_visible_column then TRANSPARENT
            else
              palette_high = ((@attribute_high >> bit) & 1) << PALETTE_HIGH_SHIFT # glossary: bit-at, place-bit-field
              palette_low = ((@attribute_low >> bit) & 1) << PALETTE_LOW_SHIFT # glossary: bit-at, place-bit-field
              palette_high | palette_low | pattern # glossary: bitwise-or
            end
          sprite = x_position < @sprite_visibility.first_visible_column ? TRANSPARENT : @sprite_entries[x_position]
          @composer.draw_pixel(background, sprite, x_position, scanline)
        end

        def fetch(steps)
          @fetcher.fetch_nametable_byte if (steps & RenderSchedule::FETCH_NAMETABLE) != 0 # glossary: flag-set
          @fetcher.fetch_attribute if (steps & RenderSchedule::FETCH_ATTRIBUTE) != 0 # glossary: flag-set
          @fetcher.fetch_pattern_low if (steps & RenderSchedule::FETCH_PATTERN_LOW) != 0 # glossary: flag-set
          @fetcher.fetch_pattern_high if (steps & RenderSchedule::FETCH_PATTERN_HIGH) != 0 # glossary: flag-set
        end

        def update_vram_address(steps)
          @scroll_registers.increment_coarse_x if (steps & RenderSchedule::INCREMENT_COARSE_X) != 0 # glossary: flag-set
          @scroll_registers.increment_y if (steps & RenderSchedule::INCREMENT_Y) != 0 # glossary: flag-set
          if (steps & RenderSchedule::COPY_HORIZONTAL) != 0 # glossary: flag-set
            @scroll_registers.copy_horizontal_position
          end
          @scroll_registers.copy_vertical_position if (steps & RenderSchedule::COPY_VERTICAL) != 0 # glossary: flag-set
        end
      end
    end
  end
end
