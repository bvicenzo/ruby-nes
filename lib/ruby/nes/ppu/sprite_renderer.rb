# frozen_string_literal: true

module Ruby
  module Nes
    class Ppu
      # Runs the sprite work of each dot (plan 14): the sprite steps RenderSchedule gives, each told to its part; the
      # slot of a fetch is the dot's 8-dot group from 257, "8 sprites total, 8 cycles per sprite"
      # (https://www.nesdev.org/wiki/PPU_rendering); "OAMADDR is set to 0 during each of ticks 257–320"
      # (https://www.nesdev.org/wiki/PPU_registers). The renderer reads the line buffer's entries to compose each pixel
      # (plan 25, decision 7). The Ppu tells it the sprite settings of PPUCTRL (bit 3, the 8×8 pattern table; bit 5,
      # "Sprite size (0: 8x8 pixels; 1: 8x16 pixels)"); it passes each to its part. Hot path: `run_steps` on the
      # sprite dots, `run_slot` once per whole slot.
      #
      # Whole slots (plan 31, decision 3): a slot whose 8 dots a range covers runs as one sequence. OAMADDR is reset
      # once, since nothing within a range can change it, and the low and high fetches are made with the shared dot
      # clock on their dots, which the board's A12 watch reads (plan 28, decision 5).
      class SpriteRenderer
        FIRST_FETCH_DOT = RenderSchedule::SPRITE_FETCH_DOTS.first
        SLOT_DOTS = RenderSchedule::SPRITE_DOTS
        # The dots of a slot's low and high fetches, from its first (RenderSchedule::SPRITE_DOT_STEPS).
        LOW_FETCH_DOT = RenderSchedule::SPRITE_DOT_STEPS.index(RenderSchedule::FETCH_SPRITE_LOW)
        HIGH_FETCH_DOT = RenderSchedule::SPRITE_DOT_STEPS.index(RenderSchedule::FETCH_SPRITE_HIGH)

        # The parts wired together: the evaluation fills the secondary OAM the fetcher reads, and the fetcher loads the
        # line the renderer reads, starting with the 8×8 address the Ppu's pattern table setting reaches; whole slots
        # move the clock the Ppu shares.
        def self.build(bus:, oam:, status:, clock:)
          secondary_oam = SecondaryOam.new
          line = SpriteLine.new
          eight_by_eight = SpritePatternAddress::EightByEight.new
          new(
            oam:,
            evaluation: SpriteEvaluation.new(oam:, secondary_oam:, status:),
            fetcher: SpriteFetcher.new(bus:, secondary_oam:, line:, pattern_address: eight_by_eight),
            line:,
            eight_by_eight:,
            clock:
          )
        end

        # One keyword per part, so specs can stand in for each. The clock is required: a whole slot's fetches must move
        # the one the Ppu and the board share (plan 31).
        # rubocop:disable-next Metrics/ParameterLists
        def initialize(oam:, evaluation:, fetcher:, line:, clock:, eight_by_eight: SpritePatternAddress::EightByEight.new,
                       eight_by_sixteen: SpritePatternAddress::EightBySixteen.new)
          @oam = oam
          @evaluation = evaluation
          @fetcher = fetcher
          @line = line
          @eight_by_eight = eight_by_eight
          @eight_by_sixteen = eight_by_sixteen
          @clock = clock
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

        # The sprite steps of a dot, in flag order.
        def run_steps(steps, scanline, dot)
          @line.clear if (steps & RenderSchedule::CLEAR_SPRITE_LINE) != 0 # glossary: flag-set
          @evaluation.evaluate(scanline) if (steps & RenderSchedule::EVALUATE_SPRITES) != 0 # glossary: flag-set
          @oam.address = 0 if (steps & RenderSchedule::RESET_OAM_ADDRESS) != 0 # glossary: flag-set
          if (steps & RenderSchedule::FETCH_SPRITE_LOW) != 0 # glossary: flag-set
            @fetcher.fetch_pattern_low(slot(dot), scanline)
          end
          @fetcher.fetch_pattern_high if (steps & RenderSchedule::FETCH_SPRITE_HIGH) != 0 # glossary: flag-set
          @fetcher.load_sprite(slot(dot)) if (steps & RenderSchedule::LOAD_SPRITE) != 0 # glossary: flag-set
        end

        # The slot starting at `dot`, whose count is `elapsed_dots`, on a scanline that loads its sprites.
        def run_slot(scanline, dot, elapsed_dots)
          slot = slot(dot)
          @oam.address = 0
          @clock.elapsed_dots = elapsed_dots + LOW_FETCH_DOT
          @fetcher.fetch_pattern_low(slot, scanline)
          @clock.elapsed_dots = elapsed_dots + HIGH_FETCH_DOT
          @fetcher.fetch_pattern_high
          @fetcher.load_sprite(slot)
        end

        # The line's 256 entries, the same array for the life of the line (SpriteLine#entries).
        def line_entries = @line.entries

        # The line's 32 flags of tiles holding an opaque sprite pixel, the same array for the life of the line
        # (SpriteLine#occupied_tiles).
        def occupied_tiles = @line.occupied_tiles

        private

        def slot(dot) = (dot - FIRST_FETCH_DOT) / SLOT_DOTS
      end
    end
  end
end
