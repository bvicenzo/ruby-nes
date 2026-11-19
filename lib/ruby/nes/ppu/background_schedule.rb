# frozen_string_literal: true

module Ruby
  module Nes
    class Ppu
      # The background's work on each dot, as a set of step flags (https://www.nesdev.org/wiki/PPU_rendering,
      # https://www.nesdev.org/wiki/PPU_scrolling). On the visible (0-239) and pre-render (261) scanlines, with rendering
      # enabled (PPUMASK bits 3-4, told by the Ppu): each tile's nametable, attribute, low and high pattern fetches
      # take 2 dots each, over dots 1-256 and 321-336 (made on the first dot of each pair); "The shifters are reloaded
      # during ticks 9, 17, 25, ..., 257", and at 329 and 337 for the next line's first two tiles; coarse X increments
      # at 8, 16, ..., 256, 328 and 336, Y at 256; the horizontal copy happens at 257, the vertical copy at 280-304 of
      # the pre-render line. Visible lines draw a pixel on dots 1-256 (x = dot − 1, plan 13 decision 5); the shifters
      # move after each pixel and on 321-336. With rendering disabled, visible lines draw the forced blank on dots
      # 1-256 and nothing else happens. The nametable fetches of 257-320 and 337-340 are not made (decision 6).
      # Within a dot, the steps run in flag order. Hot path: one lookup per dot, from constant tables.
      class BackgroundSchedule
        RELOAD = 0x001
        PIXEL = 0x002
        FORCED_BLANK_PIXEL = 0x004
        SHIFT = 0x008
        FETCH_NAMETABLE = 0x010
        FETCH_ATTRIBUTE = 0x020
        FETCH_PATTERN_LOW = 0x040
        FETCH_PATTERN_HIGH = 0x080
        INCREMENT_COARSE_X = 0x100
        INCREMENT_Y = 0x200
        COPY_HORIZONTAL = 0x400
        COPY_VERTICAL = 0x800

        DOTS_PER_SCANLINE = FrameTiming::LAST_DOT + 1
        # The dots of a tile, and its fetches by the dot's place in it (the first dot of each 2-dot access); the
        # tile's last dot increments coarse X.
        TILE_DOTS = 8
        TILE_STEPS = [
          FETCH_NAMETABLE, 0, FETCH_ATTRIBUTE, 0, FETCH_PATTERN_LOW, 0, FETCH_PATTERN_HIGH, INCREMENT_COARSE_X
        ].freeze
        PIXEL_DOTS = (1..256)
        NEXT_LINE_TILE_DOTS = (321..336)
        # The reloads after the next line's two tiles, the last one past 336.
        RELOAD_DOTS = [*(9..257).step(TILE_DOTS), 329, 337].freeze
        INCREMENT_Y_DOT = 256
        COPY_HORIZONTAL_DOT = 257
        COPY_VERTICAL_DOTS = (280..304)

        class << self
          private

          # Built once at load time; the tags name each bit operation as on the hot paths.
          def visible_steps(dot)
            rendering_steps(dot) | (PIXEL_DOTS.cover?(dot) ? PIXEL : 0) # glossary: bitwise-or
          end

          def pre_render_steps(dot)
            rendering_steps(dot) | (COPY_VERTICAL_DOTS.cover?(dot) ? COPY_VERTICAL : 0) # glossary: bitwise-or
          end

          def forced_blank_steps(dot) = PIXEL_DOTS.cover?(dot) ? FORCED_BLANK_PIXEL : 0

          # The steps both rendering lines share.
          def rendering_steps(dot)
            steps = RELOAD_DOTS.include?(dot) ? RELOAD : 0
            steps |= SHIFT | TILE_STEPS[(dot - 1) % TILE_DOTS] if tile_dot?(dot) # glossary: bitwise-or
            steps |= INCREMENT_Y if dot == INCREMENT_Y_DOT # glossary: bitwise-or
            steps |= COPY_HORIZONTAL if dot == COPY_HORIZONTAL_DOT # glossary: bitwise-or
            steps
          end

          def tile_dot?(dot) = PIXEL_DOTS.cover?(dot) || NEXT_LINE_TILE_DOTS.cover?(dot)
        end

        IDLE_LINE = Array.new(DOTS_PER_SCANLINE, 0).freeze
        FORCED_BLANK_LINE = Array.new(DOTS_PER_SCANLINE) { forced_blank_steps(it) }.freeze
        VISIBLE_LINE = Array.new(DOTS_PER_SCANLINE) { visible_steps(it) }.freeze
        PRE_RENDER_LINE = Array.new(DOTS_PER_SCANLINE) { pre_render_steps(it) }.freeze

        def initialize(rendering_enabled: false)
          self.rendering_enabled = rendering_enabled
        end

        def rendering_enabled=(enabled)
          @visible_line = enabled ? VISIBLE_LINE : FORCED_BLANK_LINE
          @pre_render_line = enabled ? PRE_RENDER_LINE : IDLE_LINE
        end

        # The step flags of a dot of a scanline.
        def steps(scanline, dot)
          if scanline < FrameTiming::POST_RENDER_SCANLINE then @visible_line[dot]
          elsif scanline == FrameTiming::PRE_RENDER_SCANLINE then @pre_render_line[dot]
          else 0
          end
        end
      end
    end
  end
end
