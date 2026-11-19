# frozen_string_literal: true

# The sprite work of a dot (plan 14): RenderSchedule's sprite steps, each told to the part that owns it; the slot of a
# fetch is the dot's 8-dot group from 257 (https://www.nesdev.org/wiki/PPU_rendering, "8 sprites total, 8 cycles per
# sprite"). "OAMADDR is set to 0 during each of ticks 257–320" (https://www.nesdev.org/wiki/PPU_registers). A pixel is
# the line's entry at the column as the sprite layer's visibility lets it through. The Ppu tells it the PPUCTRL and
# PPUMASK settings: bit 5 "Sprite size (0: 8x8 pixels; 1: 8x16 pixels)", bit 3 the 8×8 pattern table, PPUMASK bits 4
# and 2; it passes each to its part.
RSpec.describe Ruby::Nes::Ppu::SpriteRenderer do
  describe '.build' do
    let(:bus) { Ruby::Nes::PpuBus.new(mapper: Ruby::Nes::Mappers.build(cartridge)) }
    let(:cartridge) { Cartridges.build(chr_rom: Array.new(0x12A1, 0x00) + [0x80] + Array.new(0x0D5E, 0x00)) }
    let(:oam) { OamContents.build(0 => [99, 0x2A, 0x00, 0x40]) }
    let(:status) { instance_double(Ruby::Nes::Ppu::SpriteStatus) }

    it 'assembles parts that share the 8×8 address: a sprite fetched from the table PPUCTRL selects shows at its X' do
      sprite_renderer = described_class.build(bus:, oam:, status:)
      sprite_renderer.pattern_table = 0x1000
      sprite_renderer.enabled = true
      sprite_renderer.left_columns_shown = true
      sprite_renderer.run_steps(Ruby::Nes::Ppu::RenderSchedule::EVALUATE_SPRITES, 100, 257)
      sprite_renderer.run_steps(Ruby::Nes::Ppu::RenderSchedule::FETCH_SPRITE_LOW, 100, 261)
      sprite_renderer.run_steps(
        Ruby::Nes::Ppu::RenderSchedule::FETCH_SPRITE_HIGH | Ruby::Nes::Ppu::RenderSchedule::LOAD_SPRITE,
        100,
        263
      )
      expect(sprite_renderer.pixel(0x40)).to eq(0x51)
    end
  end

  describe '#run_steps' do
    subject(:sprite_renderer) { described_class.new(oam:, evaluation:, fetcher:, line:) }

    let(:oam) { Ruby::Nes::Ppu::Oam.new(address: 0x40) }
    let(:evaluation) { instance_double(Ruby::Nes::Ppu::SpriteEvaluation, evaluate: nil) }
    let(:fetcher) do
      instance_double(
        Ruby::Nes::Ppu::SpriteFetcher,
        fetch_pattern_low: 0,
        fetch_pattern_high: 0,
        load_sprite: nil
      )
    end
    let(:line) { instance_double(Ruby::Nes::Ppu::SpriteLine, clear: nil) }

    context 'when the steps clear the sprite line' do
      before { sprite_renderer.run_steps(Ruby::Nes::Ppu::RenderSchedule::CLEAR_SPRITE_LINE, 100, 257) }

      it 'clears the line' do
        expect(line).to have_received(:clear)
      end
    end

    context 'when the steps evaluate the sprites' do
      before { sprite_renderer.run_steps(Ruby::Nes::Ppu::RenderSchedule::EVALUATE_SPRITES, 100, 257) }

      it 'evaluates the sprites of the scanline' do
        expect(evaluation).to have_received(:evaluate).with(100)
      end
    end

    context 'when the steps reset OAMADDR' do
      before { sprite_renderer.run_steps(Ruby::Nes::Ppu::RenderSchedule::RESET_OAM_ADDRESS, 100, 300) }

      it 'sets OAMADDR to 0' do
        expect(oam.address).to eq(0)
      end
    end

    context 'when the steps fetch a low pattern byte' do
      before { sprite_renderer.run_steps(Ruby::Nes::Ppu::RenderSchedule::FETCH_SPRITE_LOW, 100, 269) }

      it "fetches the low byte of the dot's slot on the scanline" do
        expect(fetcher).to have_received(:fetch_pattern_low).with(1, 100)
      end
    end

    context 'when the steps fetch a high pattern byte' do
      before { sprite_renderer.run_steps(Ruby::Nes::Ppu::RenderSchedule::FETCH_SPRITE_HIGH, 100, 271) }

      it 'fetches the high byte' do
        expect(fetcher).to have_received(:fetch_pattern_high)
      end
    end

    context 'when the steps load a sprite' do
      before { sprite_renderer.run_steps(Ruby::Nes::Ppu::RenderSchedule::LOAD_SPRITE, 100, 319) }

      it "loads the dot's slot" do
        expect(fetcher).to have_received(:load_sprite).with(7)
      end
    end

    context 'when the steps fetch a high pattern byte and load a sprite' do
      before do
        steps = Ruby::Nes::Ppu::RenderSchedule::FETCH_SPRITE_HIGH | Ruby::Nes::Ppu::RenderSchedule::LOAD_SPRITE
        sprite_renderer.run_steps(steps, 100, 263)
      end

      it 'fetches before loading', :aggregate_failures do
        expect(fetcher).to have_received(:fetch_pattern_high).ordered
        expect(fetcher).to have_received(:load_sprite).with(0).ordered
      end
    end
  end

  describe '#pixel' do
    subject(:sprite_renderer) { described_class.new(oam:, evaluation:, fetcher:, line:, visibility:) }

    let(:oam) { Ruby::Nes::Ppu::Oam.new }
    let(:evaluation) { instance_double(Ruby::Nes::Ppu::SpriteEvaluation) }
    let(:fetcher) { instance_double(Ruby::Nes::Ppu::SpriteFetcher) }
    let(:line) { instance_double(Ruby::Nes::Ppu::SpriteLine) }
    let(:visibility) { instance_double(Ruby::Nes::Ppu::LayerVisibility) }

    before do
      allow(line).to receive(:entry).with(100).and_return(0x51)
      allow(visibility).to receive(:palette_entry).with(100, 0x51).and_return(0x51)
    end

    it "is the visible entry of the line's pixel at the column" do
      expect(sprite_renderer.pixel(100)).to eq(0x51)
    end
  end

  describe '#tall_sprites=' do
    subject(:sprite_renderer) do
      described_class.new(oam:, evaluation:, fetcher:, line:, eight_by_eight:, eight_by_sixteen:)
    end

    let(:oam) { Ruby::Nes::Ppu::Oam.new }
    let(:evaluation) { instance_double(Ruby::Nes::Ppu::SpriteEvaluation, :sprite_height= => nil) }
    let(:fetcher) { instance_double(Ruby::Nes::Ppu::SpriteFetcher, :pattern_address= => nil) }
    let(:line) { instance_double(Ruby::Nes::Ppu::SpriteLine) }
    let(:eight_by_eight) { instance_double(Ruby::Nes::Ppu::SpritePatternAddress::EightByEight, height: 8) }
    let(:eight_by_sixteen) { instance_double(Ruby::Nes::Ppu::SpritePatternAddress::EightBySixteen, height: 16) }

    context 'when they are turned off' do
      it 'tells the fetcher the 8×8 address and the evaluation its height', :aggregate_failures do
        sprite_renderer.tall_sprites = false
        expect(fetcher).to have_received(:pattern_address=).with(eight_by_eight)
        expect(evaluation).to have_received(:sprite_height=).with(8)
      end
    end

    context 'when they are turned on' do
      it 'tells the fetcher the 8×16 address and the evaluation its height', :aggregate_failures do
        sprite_renderer.tall_sprites = true
        expect(fetcher).to have_received(:pattern_address=).with(eight_by_sixteen)
        expect(evaluation).to have_received(:sprite_height=).with(16)
      end
    end
  end

  describe '#pattern_table=' do
    subject(:sprite_renderer) { described_class.new(oam:, evaluation:, fetcher:, line:, eight_by_eight:) }

    let(:oam) { Ruby::Nes::Ppu::Oam.new }
    let(:evaluation) { instance_double(Ruby::Nes::Ppu::SpriteEvaluation) }
    let(:fetcher) { instance_double(Ruby::Nes::Ppu::SpriteFetcher) }
    let(:line) { instance_double(Ruby::Nes::Ppu::SpriteLine) }
    let(:eight_by_eight) do
      instance_double(Ruby::Nes::Ppu::SpritePatternAddress::EightByEight, :pattern_table= => nil)
    end

    it 'tells the 8×8 address' do
      sprite_renderer.pattern_table = 0x1000
      expect(eight_by_eight).to have_received(:pattern_table=).with(0x1000)
    end
  end

  describe '#enabled=' do
    subject(:sprite_renderer) { described_class.new(oam:, evaluation:, fetcher:, line:, visibility:) }

    let(:oam) { Ruby::Nes::Ppu::Oam.new }
    let(:evaluation) { instance_double(Ruby::Nes::Ppu::SpriteEvaluation) }
    let(:fetcher) { instance_double(Ruby::Nes::Ppu::SpriteFetcher) }
    let(:line) { instance_double(Ruby::Nes::Ppu::SpriteLine) }
    let(:visibility) { instance_double(Ruby::Nes::Ppu::LayerVisibility, :enabled= => nil) }

    it 'tells the visibility' do
      sprite_renderer.enabled = true
      expect(visibility).to have_received(:enabled=).with(true)
    end
  end

  describe '#left_columns_shown=' do
    subject(:sprite_renderer) { described_class.new(oam:, evaluation:, fetcher:, line:, visibility:) }

    let(:oam) { Ruby::Nes::Ppu::Oam.new }
    let(:evaluation) { instance_double(Ruby::Nes::Ppu::SpriteEvaluation) }
    let(:fetcher) { instance_double(Ruby::Nes::Ppu::SpriteFetcher) }
    let(:line) { instance_double(Ruby::Nes::Ppu::SpriteLine) }
    let(:visibility) { instance_double(Ruby::Nes::Ppu::LayerVisibility, :left_columns_shown= => nil) }

    it 'tells the visibility' do
      sprite_renderer.left_columns_shown = true
      expect(visibility).to have_received(:left_columns_shown=).with(true)
    end
  end
end
