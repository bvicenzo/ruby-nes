# frozen_string_literal: true

module Ruby
  module Nes
    class Ppu
      # Runs the sprite work of each dot (plan 14): the sprite steps RenderSchedule gives, each told to its part; the
      # slot of a fetch is the dot's 8-dot group from 257, "8 sprites total, 8 cycles per sprite"
      # (https://www.nesdev.org/wiki/PPU_rendering); "OAMADDR is set to 0 during each of ticks 257–320"
      # (https://www.nesdev.org/wiki/PPU_registers). A pixel is the line buffer's entry as the sprite layer's
      # visibility lets it through. The Ppu tells it the sprite settings of PPUCTRL (bit 3, the 8×8 pattern table; bit
      # 5, "Sprite size (0: 8x8 pixels; 1: 8x16 pixels)") and PPUMASK (bits 4 and 2); it passes each to its part.
      # Hot path: `run_steps` on the sprite dots, `pixel` once per visible dot.
      class SpriteRenderer
        FIRST_FETCH_DOT = RenderSchedule::SPRITE_FETCH_DOTS.first
        SLOT_DOTS = RenderSchedule::SPRITE_DOTS

        # The parts wired together: the evaluation fills the secondary OAM the fetcher reads, and the fetcher loads the
        # line `pixel` reads, starting with the 8×8 address the Ppu's pattern table setting reaches.
        def self.build(bus:, oam:, status:)
          secondary_oam = SecondaryOam.new
          line = SpriteLine.new
          eight_by_eight = SpritePatternAddress::EightByEight.new
          new(
            oam:,
            evaluation: SpriteEvaluation.new(oam:, secondary_oam:, status:),
            fetcher: SpriteFetcher.new(bus:, secondary_oam:, line:, pattern_address: eight_by_eight),
            line:,
            eight_by_eight:
          )
        end

        # One optional keyword per part, so specs can stand in for each.
        # rubocop:disable-next Metrics/ParameterLists
        def initialize(oam:, evaluation:, fetcher:, line:, visibility: LayerVisibility.new,
                       eight_by_eight: SpritePatternAddress::EightByEight.new,
                       eight_by_sixteen: SpritePatternAddress::EightBySixteen.new)
          @oam = oam
          @evaluation = evaluation
          @fetcher = fetcher
          @line = line
          @visibility = visibility
          @eight_by_eight = eight_by_eight
          @eight_by_sixteen = eight_by_sixteen
        end

        def pattern_table=(address)
          @eight_by_eight.pattern_table = address
        end

        # 8×16 sprites (PPUCTRL bit 5) or 8×8: the fetcher takes that size's pattern address, the evaluation its height.
        def tall_sprites=(enabled)
          pattern_address = enabled ? @eight_by_sixteen : @eight_by_eight
          @fetcher.pattern_address = pattern_address
          @evaluation.sprite_height = pattern_address.height
        end

        def enabled=(enabled)
          @visibility.enabled = enabled
        end

        def left_columns_shown=(shown)
          @visibility.left_columns_shown = shown
        end

        # The sprite steps of a dot, in flag order.
        def run_steps(steps, scanline, dot)
          @line.clear if steps.anybits?(RenderSchedule::CLEAR_SPRITE_LINE)
          @evaluation.evaluate(scanline) if steps.anybits?(RenderSchedule::EVALUATE_SPRITES)
          @oam.address = 0 if steps.anybits?(RenderSchedule::RESET_OAM_ADDRESS)
          @fetcher.fetch_pattern_low(slot(dot), scanline) if steps.anybits?(RenderSchedule::FETCH_SPRITE_LOW)
          @fetcher.fetch_pattern_high if steps.anybits?(RenderSchedule::FETCH_SPRITE_HIGH)
          @fetcher.load_sprite(slot(dot)) if steps.anybits?(RenderSchedule::LOAD_SPRITE)
        end

        # The sprite layer's palette entry at column x, with SpriteLine's flags: 0 when no visible sprite pixel.
        def pixel(x_position) = @visibility.palette_entry(x_position, @line.entry(x_position))

        private

        def slot(dot) = (dot - FIRST_FETCH_DOT) / SLOT_DOTS
      end
    end
  end
end
