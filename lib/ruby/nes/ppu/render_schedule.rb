# frozen_string_literal: true

module Ruby
  module Nes
    class Ppu
      # The rendering work of each dot, as a set of step flags (https://www.nesdev.org/wiki/PPU_rendering,
      # https://www.nesdev.org/wiki/PPU_scrolling). On the visible (0-239) and pre-render (261) scanlines, with rendering
      # enabled (PPUMASK bits 3-4, told by the Ppu): each tile's nametable, attribute, low and high pattern fetches
      # take 2 dots each, over dots 1-256 and 321-336 (made on the first dot of each pair); "The shifters are reloaded
      # during ticks 9, 17, 25, ..., 257", and at 329 and 337 for the next line's first two tiles; coarse X increments
      # at 8, 16, ..., 256, 328 and 336, Y at 256; the horizontal copy happens at 257, the vertical copy at 280-304 of
      # the pre-render line. Visible lines draw a pixel on dots 1-256 (x = dot − 1, plan 13 decision 5); the shifters
      # move after each pixel and on 321-336. With rendering disabled, visible lines draw the forced blank on dots
      # 1-256 and nothing else happens but the sprite line's clear. The nametable fetches of 257-320 and 337-340 are not made (decision 6).
      #
      # Sprites (plan 14): visible lines clear the sprite line and evaluate the next line's sprites at dot 257
      # (decision 2); "Sprite evaluation does not happen on the pre-render scanline"
      # (https://www.nesdev.org/wiki/PPU_sprite_evaluation), which only clears the line, so line 0 shows no sprite.
      # Dots 257-320 fetch 8 sprites of 8 dots, the low and high pattern fetches at 261 + 8k and 263 + 8k (decision 3);
      # visible lines load each sprite into the line after its high fetch, the pre-render line loads nothing. "OAMADDR
      # is set to 0 during each of ticks 257–320" (https://www.nesdev.org/wiki/PPU_registers). With rendering disabled,
      # visible and pre-render lines still clear the sprite line at 257: nothing is fetched, and an output unit shows
      # its row only on the line after its fetch (a derivation, https://www.nesdev.org/wiki/PPU_OAM).
      # Within a dot, the steps run in flag order. Hot path: one line per range of dots, from constant tables.
      class RenderSchedule
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
        CLEAR_SPRITE_LINE = 0x1000
        EVALUATE_SPRITES = 0x2000
        RESET_OAM_ADDRESS = 0x4000
        FETCH_SPRITE_LOW = 0x8000
        FETCH_SPRITE_HIGH = 0x10000
        LOAD_SPRITE = 0x20000
        # The first dot of a tile a visible line draws: its 8 dots draw, shift and fetch the same way on every tile (only
        # the reload before the first and the Y increment of the last differ), so a range that covers them can run them
        # as one sequence (plan 28, decision 6).
        WHOLE_TILE = 0x40000
        # The steps the sprite renderer runs.
        SPRITE_STEPS =
          CLEAR_SPRITE_LINE |
          EVALUATE_SPRITES |
          RESET_OAM_ADDRESS |
          FETCH_SPRITE_LOW |
          FETCH_SPRITE_HIGH |
          LOAD_SPRITE

        DOTS_PER_SCANLINE = FrameTiming::DOTS_PER_SCANLINE
        # The dots of a tile, and its fetches by the dot's place in it (the first dot of each 2-dot access); the
        # tile's last dot increments coarse X.
        TILE_DOTS = 8
        TILE_STEPS = [
          FETCH_NAMETABLE, 0, FETCH_ATTRIBUTE, 0, FETCH_PATTERN_LOW, 0, FETCH_PATTERN_HIGH, INCREMENT_COARSE_X
        ].freeze
        PIXEL_DOTS = (1..256)
        WHOLE_TILE_DOTS = PIXEL_DOTS.step(TILE_DOTS)
        NEXT_LINE_TILE_DOTS = (321..336)
        # The reloads after the next line's two tiles, the last one past 336.
        RELOAD_DOTS = [*(9..257).step(TILE_DOTS), 329, 337].freeze
        INCREMENT_Y_DOT = 256
        COPY_HORIZONTAL_DOT = 257
        COPY_VERTICAL_DOTS = (280..304)
        # The sprite fetches: 8 sprites of 8 dots from 257, the low and high pattern fetches being their third and fourth
        # 2-dot accesses; OAMADDR is 0 through all of them.
        SPRITE_FETCH_DOTS = (257..320)
        SPRITE_DOTS = 8
        SPRITE_DOT_STEPS = [0, 0, 0, 0, FETCH_SPRITE_LOW, 0, FETCH_SPRITE_HIGH, 0].freeze
        SPRITE_EVALUATION_DOT = 257

        class << self
          private

          # Built once at load time; the tags name each bit operation as on the hot paths.
          def visible_steps(dot)
            steps = rendering_steps(dot) | (PIXEL_DOTS.cover?(dot) ? PIXEL : 0) # glossary: bitwise-or
            steps |= EVALUATE_SPRITES if dot == SPRITE_EVALUATION_DOT # glossary: bitwise-or
            steps |= WHOLE_TILE if WHOLE_TILE_DOTS.include?(dot) # glossary: bitwise-or
            steps |= LOAD_SPRITE if steps.anybits?(FETCH_SPRITE_HIGH) # glossary: bitwise-or
            steps
          end

          def pre_render_steps(dot)
            rendering_steps(dot) | (COPY_VERTICAL_DOTS.cover?(dot) ? COPY_VERTICAL : 0) # glossary: bitwise-or
          end

          def forced_blank_steps(dot)
            (PIXEL_DOTS.cover?(dot) ? FORCED_BLANK_PIXEL : 0) | idle_steps(dot) # glossary: bitwise-or
          end

          # With rendering disabled no sprite is fetched: the line is cleared where a rendering line would reload it.
          def idle_steps(dot) = dot == SPRITE_EVALUATION_DOT ? CLEAR_SPRITE_LINE : 0

          # The steps both rendering lines share.
          def rendering_steps(dot)
            steps = RELOAD_DOTS.include?(dot) ? RELOAD : 0
            steps |= SHIFT | TILE_STEPS[(dot - 1) % TILE_DOTS] if tile_dot?(dot) # glossary: bitwise-or
            steps |= INCREMENT_Y if dot == INCREMENT_Y_DOT # glossary: bitwise-or
            steps |= COPY_HORIZONTAL if dot == COPY_HORIZONTAL_DOT # glossary: bitwise-or
            steps | sprite_steps(dot) # glossary: bitwise-or
          end

          # The sprite steps both rendering lines share.
          def sprite_steps(dot)
            return 0 unless SPRITE_FETCH_DOTS.cover?(dot)

            sprite_dot = (dot - SPRITE_FETCH_DOTS.first) % SPRITE_DOTS
            steps = RESET_OAM_ADDRESS | SPRITE_DOT_STEPS[sprite_dot] # glossary: bitwise-or
            steps |= CLEAR_SPRITE_LINE if dot == SPRITE_EVALUATION_DOT # glossary: bitwise-or
            steps
          end

          def tile_dot?(dot) = PIXEL_DOTS.cover?(dot) || NEXT_LINE_TILE_DOTS.cover?(dot)
        end

        # The post-render and VBlank scanlines do nothing.
        BLANK_LINE = Array.new(DOTS_PER_SCANLINE, 0).freeze
        IDLE_LINE = Array.new(DOTS_PER_SCANLINE) { idle_steps(it) }.freeze
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

        # The step flags of each dot of a scanline, indexed by dot: one frozen array per kind of line, so a range of
        # dots reads its line once (plan 28, decision 4).
        def line(scanline)
          if scanline < FrameTiming::POST_RENDER_SCANLINE then @visible_line
          elsif scanline == FrameTiming::PRE_RENDER_SCANLINE then @pre_render_line
          else BLANK_LINE
          end
        end
      end
    end
  end
end
