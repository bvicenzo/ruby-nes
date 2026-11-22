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
      # sprites' comes from the sprite renderer's line entries. Where only one layer is opaque its entry is drawn, a
      # sprite's without SpriteLine's priority and sprite 0 marks; only where both are does the priority multiplexer
      # decide, checking the sprite 0 hit (https://www.nesdev.org/wiki/PPU_sprite_priority). The sprite steps go to the
      # sprite renderer. The Ppu tells it the background's PPUCTRL settings and the PPUMASK settings; it passes each to
      # the part that uses it. Hot path: one `run_dot` per PPU dot. The pixel is composed here, with the registers as
      # instance variables and the sprite line read as an array, rather than through one object per stage: a method call
      # costs about 5 ns under YJIT, and the stages cost about a third of a frame (plan 25).
      class Renderer
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
        SPRITE_PALETTE_ENTRY_MASK = SpriteLine::PALETTE_ENTRY_MASK

        # One optional keyword per part, so specs can stand in for each.
        # rubocop:disable-next Metrics/ParameterLists
        def initialize(scroll_registers:, fetcher:, picture:, sprite_renderer:, multiplexer:,
                       schedule: RenderSchedule.new, background_visibility: LayerVisibility.new,
                       sprite_visibility: LayerVisibility.new)
          @scroll_registers = scroll_registers
          @fetcher = fetcher
          @picture = picture
          @sprite_renderer = sprite_renderer
          @sprite_entries = sprite_renderer.line_entries
          @multiplexer = multiplexer
          @schedule = schedule
          @background_visibility = background_visibility
          @sprite_visibility = sprite_visibility
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

        # The PPU entered the post-render scanline: the frame drawn becomes the frame buffer (plan 16, decision 1).
        def complete_picture
          @picture.complete_frame
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

        def run_dot(scanline, dot)
          steps = @schedule.steps(scanline, dot)
          return if steps.zero?

          output_pixel(steps, scanline, dot)
          fetch(steps)
          update_vram_address(steps)
          return if (steps & RenderSchedule::SPRITE_STEPS) == 0 # glossary: flag-clear

          @sprite_renderer.run_steps(steps, scanline, dot)
        end

        private

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

        # The background's 4 bits under fine X (0 when transparent or hidden), the sprite line's entry at x (0 when
        # hidden), then the entry drawn: one opaque layer as it is, a sprite without its marks; both go to the priority
        # multiplexer. One method, no call per stage: each call costs about 5 ns per visible dot (plan 25).
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
          entry =
            if sprite == TRANSPARENT then background
            elsif background == TRANSPARENT then sprite & SPRITE_PALETTE_ENTRY_MASK # glossary: low-bits
            else @multiplexer.palette_entry(x_position, background, sprite)
            end
          @picture.draw(x_position, scanline, entry)
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
