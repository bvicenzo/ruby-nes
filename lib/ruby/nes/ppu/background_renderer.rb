# frozen_string_literal: true

module Ruby
  module Nes
    class Ppu
      # Runs the background's work of each dot (plan 13): the schedule gives the steps, in order; the renderer tells
      # each part. A reload puts the fetched tile behind the one on screen before the dot's pixel; the pixel, the
      # shifters' 4 bits under fine X as the visibility lets them through, goes to x = dot − 1 of the scanline (decision
      # 5), and the shifters move after it. The Ppu tells it the PPUCTRL and PPUMASK settings; it passes each to the part
      # that uses it. Hot path: one `run_dot` per PPU dot.
      class BackgroundRenderer
        # One optional keyword per part, so specs can stand in for each.
        # rubocop:disable-next Metrics/ParameterLists
        def initialize(scroll_registers:, fetcher:, picture:, schedule: BackgroundSchedule.new,
                       shifters: BackgroundShifters.new, visibility: BackgroundVisibility.new)
          @scroll_registers = scroll_registers
          @fetcher = fetcher
          @picture = picture
          @schedule = schedule
          @shifters = shifters
          @visibility = visibility
        end

        def frame_buffer = @picture.frame_buffer

        def pattern_table=(address)
          @fetcher.pattern_table = address
        end

        def greyscale=(enabled)
          @picture.greyscale = enabled
        end

        def background_enabled=(enabled)
          @visibility.background_enabled = enabled
        end

        def left_columns_shown=(shown)
          @visibility.left_columns_shown = shown
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
        end

        private

        def output_pixel(steps, scanline, dot)
          if steps.anybits?(BackgroundSchedule::RELOAD)
            @shifters.reload(@fetcher.pattern_low, @fetcher.pattern_high, @fetcher.palette)
          end
          draw(scanline, dot - 1) if steps.anybits?(BackgroundSchedule::PIXEL)
          if steps.anybits?(BackgroundSchedule::FORCED_BLANK_PIXEL)
            @picture.draw_forced_blank(dot - 1, scanline, @scroll_registers.vram_address)
          end
          @shifters.shift if steps.anybits?(BackgroundSchedule::SHIFT)
        end

        def draw(scanline, x_position)
          pixel = @shifters.pixel(@scroll_registers.fine_x)
          @picture.draw(x_position, scanline, @visibility.palette_entry(x_position, pixel))
        end

        def fetch(steps)
          @fetcher.fetch_nametable_byte if steps.anybits?(BackgroundSchedule::FETCH_NAMETABLE)
          @fetcher.fetch_attribute if steps.anybits?(BackgroundSchedule::FETCH_ATTRIBUTE)
          @fetcher.fetch_pattern_low if steps.anybits?(BackgroundSchedule::FETCH_PATTERN_LOW)
          @fetcher.fetch_pattern_high if steps.anybits?(BackgroundSchedule::FETCH_PATTERN_HIGH)
        end

        def update_vram_address(steps)
          @scroll_registers.increment_coarse_x if steps.anybits?(BackgroundSchedule::INCREMENT_COARSE_X)
          @scroll_registers.increment_y if steps.anybits?(BackgroundSchedule::INCREMENT_Y)
          @scroll_registers.copy_horizontal_position if steps.anybits?(BackgroundSchedule::COPY_HORIZONTAL)
          @scroll_registers.copy_vertical_position if steps.anybits?(BackgroundSchedule::COPY_VERTICAL)
        end
      end
    end
  end
end
