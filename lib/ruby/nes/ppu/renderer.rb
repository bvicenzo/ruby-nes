# frozen_string_literal: true

module Ruby
  module Nes
    class Ppu
      # Runs the rendering work of each dot (plans 13 and 14): the schedule gives the steps, in order; the renderer
      # tells each part. A reload puts the fetched tile behind the one on screen before the dot's pixel; the pixel goes
      # to x = dot − 1 of the scanline (plan 13, decision 5), the priority multiplexer choosing between the shifters' 4
      # bits under fine X, as the background's visibility lets them through, and the sprite renderer's pixel; the
      # shifters move after it. The sprite steps go to the sprite renderer. The Ppu tells it the background's PPUCTRL
      # and PPUMASK settings; it passes each to the part that uses it. Hot path: one `run_dot` per PPU dot.
      class Renderer
        # One optional keyword per part, so specs can stand in for each.
        # rubocop:disable-next Metrics/ParameterLists
        def initialize(scroll_registers:, fetcher:, picture:, sprite_renderer:, multiplexer:,
                       schedule: RenderSchedule.new, shifters: BackgroundShifters.new,
                       background_visibility: LayerVisibility.new)
          @scroll_registers = scroll_registers
          @fetcher = fetcher
          @picture = picture
          @sprite_renderer = sprite_renderer
          @multiplexer = multiplexer
          @schedule = schedule
          @shifters = shifters
          @background_visibility = background_visibility
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

        def left_columns_shown=(shown)
          @background_visibility.left_columns_shown = shown
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
          @sprite_renderer.run_steps(steps, scanline, dot) if steps.anybits?(RenderSchedule::SPRITE_STEPS)
        end

        private

        def output_pixel(steps, scanline, dot)
          if steps.anybits?(RenderSchedule::RELOAD)
            @shifters.reload(@fetcher.pattern_low, @fetcher.pattern_high, @fetcher.palette)
          end
          draw(scanline, dot - 1) if steps.anybits?(RenderSchedule::PIXEL)
          if steps.anybits?(RenderSchedule::FORCED_BLANK_PIXEL)
            @picture.draw_forced_blank(dot - 1, scanline, @scroll_registers.vram_address)
          end
          @shifters.shift if steps.anybits?(RenderSchedule::SHIFT)
        end

        def draw(scanline, x_position)
          background_entry = @background_visibility.palette_entry(x_position, @shifters.pixel(@scroll_registers.fine_x))
          sprite_entry = @sprite_renderer.pixel(x_position)
          @picture.draw(x_position, scanline, @multiplexer.palette_entry(x_position, background_entry, sprite_entry))
        end

        def fetch(steps)
          @fetcher.fetch_nametable_byte if steps.anybits?(RenderSchedule::FETCH_NAMETABLE)
          @fetcher.fetch_attribute if steps.anybits?(RenderSchedule::FETCH_ATTRIBUTE)
          @fetcher.fetch_pattern_low if steps.anybits?(RenderSchedule::FETCH_PATTERN_LOW)
          @fetcher.fetch_pattern_high if steps.anybits?(RenderSchedule::FETCH_PATTERN_HIGH)
        end

        def update_vram_address(steps)
          @scroll_registers.increment_coarse_x if steps.anybits?(RenderSchedule::INCREMENT_COARSE_X)
          @scroll_registers.increment_y if steps.anybits?(RenderSchedule::INCREMENT_Y)
          @scroll_registers.copy_horizontal_position if steps.anybits?(RenderSchedule::COPY_HORIZONTAL)
          @scroll_registers.copy_vertical_position if steps.anybits?(RenderSchedule::COPY_VERTICAL)
        end
      end
    end
  end
end
