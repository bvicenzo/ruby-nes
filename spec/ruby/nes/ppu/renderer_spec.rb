# frozen_string_literal: true

# The renderer runs, on each dot, the steps the schedule gives (plan 13): reloads the shifters with the fetched tile,
# draws at x = dot - 1 of the scanline (decision 5) the pixel the priority multiplexer chooses between the shifters'
# pixel under fine X, as the background's visibility lets it through, and the sprite renderer's pixel (plan 14), or
# the forced blank, shifts, makes the fetches and updates v; a reload comes before the pixel it feeds, and the shift
# after it. The sprite steps go to the sprite renderer. It also passes the PPUCTRL and PPUMASK background settings the
# Ppu tells it to the part that uses each.
RSpec.describe Ruby::Nes::Ppu::Renderer do
  describe '#run_dot' do
    subject(:renderer) do
      described_class.new(
        scroll_registers:,
        fetcher:,
        picture:,
        sprite_renderer:,
        multiplexer:,
        schedule:,
        shifters:,
        background_visibility:
      )
    end

    let(:scroll_registers) do
      instance_double(
        Ruby::Nes::Ppu::ScrollRegisters,
        increment_coarse_x: nil,
        increment_y: nil,
        copy_horizontal_position: nil,
        copy_vertical_position: nil
      )
    end
    let(:fetcher) do
      instance_double(
        Ruby::Nes::Ppu::BackgroundFetcher,
        fetch_nametable_byte: nil,
        fetch_attribute: nil,
        fetch_pattern_low: nil,
        fetch_pattern_high: nil
      )
    end
    let(:picture) { instance_double(Ruby::Nes::Ppu::Picture, draw: nil, draw_forced_blank: nil) }
    let(:shifters) { instance_double(Ruby::Nes::Ppu::BackgroundShifters, reload: nil, shift: nil) }
    let(:background_visibility) { instance_double(Ruby::Nes::Ppu::LayerVisibility) }
    let(:sprite_renderer) { instance_double(Ruby::Nes::Ppu::SpriteRenderer, pixel: 0x00) }
    let(:multiplexer) { instance_double(Ruby::Nes::Ppu::PriorityMultiplexer) }

    context 'when the dot has no step' do
      let(:schedule) { instance_double(Ruby::Nes::Ppu::RenderSchedule, steps: 0) }

      before { renderer.run_dot(250, 300) }

      it 'touches nothing', :aggregate_failures do
        expect(picture).not_to have_received(:draw)
        expect(picture).not_to have_received(:draw_forced_blank)
        expect(shifters).not_to have_received(:reload)
        expect(shifters).not_to have_received(:shift)
        expect(fetcher).not_to have_received(:fetch_nametable_byte)
        expect(fetcher).not_to have_received(:fetch_attribute)
        expect(fetcher).not_to have_received(:fetch_pattern_low)
        expect(fetcher).not_to have_received(:fetch_pattern_high)
        expect(scroll_registers).not_to have_received(:increment_coarse_x)
        expect(scroll_registers).not_to have_received(:increment_y)
        expect(scroll_registers).not_to have_received(:copy_horizontal_position)
        expect(scroll_registers).not_to have_received(:copy_vertical_position)
      end
    end

    context 'when the dot reloads the shifters' do
      let(:schedule) do
        instance_double(Ruby::Nes::Ppu::RenderSchedule, steps: Ruby::Nes::Ppu::RenderSchedule::RELOAD)
      end

      before do
        allow(fetcher).to receive_messages(pattern_low: 0x5A, pattern_high: 0xC3, palette: 2)
        renderer.run_dot(10, 9)
      end

      it "reloads them with the fetched tile's pattern bytes and palette" do
        expect(shifters).to have_received(:reload).with(0x5A, 0xC3, 2)
      end
    end

    context 'when the dot draws a pixel' do
      let(:schedule) do
        instance_double(Ruby::Nes::Ppu::RenderSchedule, steps: Ruby::Nes::Ppu::RenderSchedule::PIXEL)
      end

      before do
        allow(scroll_registers).to receive(:fine_x).and_return(3)
        allow(shifters).to receive(:pixel).with(3).and_return(0b10_01)
        allow(background_visibility).to receive(:palette_entry).with(9, 0b10_01).and_return(0b10_01)
        allow(sprite_renderer).to receive(:pixel).with(9).and_return(0x51)
        allow(multiplexer).to receive(:palette_entry).with(9, 0b10_01, 0x51).and_return(0x11)
        renderer.run_dot(239, 10)
      end

      it "draws at x dot - 1 of the scanline the multiplexer's entry for the visible background and sprite pixels" do
        expect(picture).to have_received(:draw).with(9, 239, 0x11)
      end
    end

    context 'when the dot draws a forced blank pixel' do
      let(:schedule) do
        instance_double(
          Ruby::Nes::Ppu::RenderSchedule,
          steps: Ruby::Nes::Ppu::RenderSchedule::FORCED_BLANK_PIXEL
        )
      end

      before do
        allow(scroll_registers).to receive(:vram_address).and_return(0x3F05)
        renderer.run_dot(239, 10)
      end

      it 'draws the forced blank at x dot - 1 of the scanline with v' do
        expect(picture).to have_received(:draw_forced_blank).with(9, 239, 0x3F05)
      end
    end

    context 'when the dot shifts' do
      let(:schedule) do
        instance_double(Ruby::Nes::Ppu::RenderSchedule, steps: Ruby::Nes::Ppu::RenderSchedule::SHIFT)
      end

      before { renderer.run_dot(261, 321) }

      it 'shifts the shifters' do
        expect(shifters).to have_received(:shift)
      end
    end

    context 'when the dot fetches the nametable byte' do
      let(:schedule) do
        instance_double(
          Ruby::Nes::Ppu::RenderSchedule,
          steps: Ruby::Nes::Ppu::RenderSchedule::FETCH_NAMETABLE
        )
      end

      before { renderer.run_dot(0, 1) }

      it 'fetches it' do
        expect(fetcher).to have_received(:fetch_nametable_byte)
      end
    end

    context 'when the dot fetches the attribute byte' do
      let(:schedule) do
        instance_double(
          Ruby::Nes::Ppu::RenderSchedule,
          steps: Ruby::Nes::Ppu::RenderSchedule::FETCH_ATTRIBUTE
        )
      end

      before { renderer.run_dot(0, 3) }

      it 'fetches it' do
        expect(fetcher).to have_received(:fetch_attribute)
      end
    end

    context 'when the dot fetches the low pattern byte' do
      let(:schedule) do
        instance_double(
          Ruby::Nes::Ppu::RenderSchedule,
          steps: Ruby::Nes::Ppu::RenderSchedule::FETCH_PATTERN_LOW
        )
      end

      before { renderer.run_dot(0, 5) }

      it 'fetches it' do
        expect(fetcher).to have_received(:fetch_pattern_low)
      end
    end

    context 'when the dot fetches the high pattern byte' do
      let(:schedule) do
        instance_double(
          Ruby::Nes::Ppu::RenderSchedule,
          steps: Ruby::Nes::Ppu::RenderSchedule::FETCH_PATTERN_HIGH
        )
      end

      before { renderer.run_dot(0, 7) }

      it 'fetches it' do
        expect(fetcher).to have_received(:fetch_pattern_high)
      end
    end

    context 'when the dot increments coarse X' do
      let(:schedule) do
        instance_double(
          Ruby::Nes::Ppu::RenderSchedule,
          steps: Ruby::Nes::Ppu::RenderSchedule::INCREMENT_COARSE_X
        )
      end

      before { renderer.run_dot(0, 8) }

      it 'increments it in v' do
        expect(scroll_registers).to have_received(:increment_coarse_x)
      end
    end

    context 'when the dot increments Y' do
      let(:schedule) do
        instance_double(Ruby::Nes::Ppu::RenderSchedule, steps: Ruby::Nes::Ppu::RenderSchedule::INCREMENT_Y)
      end

      before { renderer.run_dot(0, 256) }

      it 'increments it in v' do
        expect(scroll_registers).to have_received(:increment_y)
      end
    end

    context 'when the dot copies the horizontal position' do
      let(:schedule) do
        instance_double(
          Ruby::Nes::Ppu::RenderSchedule,
          steps: Ruby::Nes::Ppu::RenderSchedule::COPY_HORIZONTAL
        )
      end

      before { renderer.run_dot(0, 257) }

      it 'copies it from t to v' do
        expect(scroll_registers).to have_received(:copy_horizontal_position)
      end
    end

    context 'when the dot copies the vertical position' do
      let(:schedule) do
        instance_double(
          Ruby::Nes::Ppu::RenderSchedule,
          steps: Ruby::Nes::Ppu::RenderSchedule::COPY_VERTICAL
        )
      end

      before { renderer.run_dot(261, 280) }

      it 'copies it from t to v' do
        expect(scroll_registers).to have_received(:copy_vertical_position)
      end
    end

    context 'when the dot has sprite steps' do
      let(:schedule) do
        instance_double(
          Ruby::Nes::Ppu::RenderSchedule,
          steps: Ruby::Nes::Ppu::RenderSchedule::FETCH_SPRITE_HIGH | Ruby::Nes::Ppu::RenderSchedule::LOAD_SPRITE
        )
      end

      before do
        allow(sprite_renderer).to receive(:run_steps)
        renderer.run_dot(100, 263)
      end

      it 'tells the sprite renderer the steps, the scanline and the dot' do
        expect(sprite_renderer).to have_received(:run_steps).with(
          Ruby::Nes::Ppu::RenderSchedule::FETCH_SPRITE_HIGH | Ruby::Nes::Ppu::RenderSchedule::LOAD_SPRITE,
          100,
          263
        )
      end
    end

    context 'when the dot reloads, draws a pixel and shifts' do
      let(:schedule) do
        instance_double(
          Ruby::Nes::Ppu::RenderSchedule,
          steps: Ruby::Nes::Ppu::RenderSchedule::RELOAD |
            Ruby::Nes::Ppu::RenderSchedule::PIXEL |
            Ruby::Nes::Ppu::RenderSchedule::SHIFT
        )
      end

      before do
        allow(fetcher).to receive_messages(pattern_low: 0x5A, pattern_high: 0xC3, palette: 2)
        allow(scroll_registers).to receive(:fine_x).and_return(0)
        allow(shifters).to receive(:pixel).with(0).and_return(0b10_01)
        allow(background_visibility).to receive(:palette_entry).with(8, 0b10_01).and_return(0b10_01)
        allow(multiplexer).to receive(:palette_entry).with(8, 0b10_01, 0x00).and_return(0b10_01)
        renderer.run_dot(0, 9)
      end

      it 'reloads, then draws, then shifts', :aggregate_failures do
        expect(shifters).to have_received(:reload).ordered
        expect(shifters).to have_received(:pixel).ordered
        expect(shifters).to have_received(:shift).ordered
      end
    end
  end

  describe '#pattern_table=' do
    subject(:renderer) { described_class.new(scroll_registers:, fetcher:, picture:, sprite_renderer:, multiplexer:) }

    let(:scroll_registers) { instance_double(Ruby::Nes::Ppu::ScrollRegisters) }
    let(:fetcher) { instance_double(Ruby::Nes::Ppu::BackgroundFetcher, :pattern_table= => nil) }
    let(:picture) { instance_double(Ruby::Nes::Ppu::Picture) }
    let(:sprite_renderer) { instance_double(Ruby::Nes::Ppu::SpriteRenderer) }
    let(:multiplexer) { instance_double(Ruby::Nes::Ppu::PriorityMultiplexer) }

    it 'tells the fetcher' do
      renderer.pattern_table = 0x1000
      expect(fetcher).to have_received(:pattern_table=).with(0x1000)
    end
  end

  describe '#greyscale=' do
    subject(:renderer) { described_class.new(scroll_registers:, fetcher:, picture:, sprite_renderer:, multiplexer:) }

    let(:scroll_registers) { instance_double(Ruby::Nes::Ppu::ScrollRegisters) }
    let(:fetcher) { instance_double(Ruby::Nes::Ppu::BackgroundFetcher) }
    let(:picture) { instance_double(Ruby::Nes::Ppu::Picture, :greyscale= => nil) }
    let(:sprite_renderer) { instance_double(Ruby::Nes::Ppu::SpriteRenderer) }
    let(:multiplexer) { instance_double(Ruby::Nes::Ppu::PriorityMultiplexer) }

    it 'tells the picture' do
      renderer.greyscale = true
      expect(picture).to have_received(:greyscale=).with(true)
    end
  end

  describe '#background_enabled=' do
    subject(:renderer) do
      described_class.new(scroll_registers:, fetcher:, picture:, sprite_renderer:, multiplexer:, background_visibility:)
    end

    let(:scroll_registers) { instance_double(Ruby::Nes::Ppu::ScrollRegisters) }
    let(:fetcher) { instance_double(Ruby::Nes::Ppu::BackgroundFetcher) }
    let(:picture) { instance_double(Ruby::Nes::Ppu::Picture) }
    let(:sprite_renderer) { instance_double(Ruby::Nes::Ppu::SpriteRenderer) }
    let(:multiplexer) { instance_double(Ruby::Nes::Ppu::PriorityMultiplexer) }
    let(:background_visibility) { instance_double(Ruby::Nes::Ppu::LayerVisibility, :enabled= => nil) }

    it 'tells the visibility' do
      renderer.background_enabled = true
      expect(background_visibility).to have_received(:enabled=).with(true)
    end
  end

  describe '#left_columns_shown=' do
    subject(:renderer) do
      described_class.new(scroll_registers:, fetcher:, picture:, sprite_renderer:, multiplexer:, background_visibility:)
    end

    let(:scroll_registers) { instance_double(Ruby::Nes::Ppu::ScrollRegisters) }
    let(:fetcher) { instance_double(Ruby::Nes::Ppu::BackgroundFetcher) }
    let(:picture) { instance_double(Ruby::Nes::Ppu::Picture) }
    let(:sprite_renderer) { instance_double(Ruby::Nes::Ppu::SpriteRenderer) }
    let(:multiplexer) { instance_double(Ruby::Nes::Ppu::PriorityMultiplexer) }
    let(:background_visibility) { instance_double(Ruby::Nes::Ppu::LayerVisibility, :left_columns_shown= => nil) }

    it 'tells the visibility' do
      renderer.left_columns_shown = true
      expect(background_visibility).to have_received(:left_columns_shown=).with(true)
    end
  end

  describe '#rendering_enabled=' do
    subject(:renderer) do
      described_class.new(scroll_registers:, fetcher:, picture:, sprite_renderer:, multiplexer:, schedule:)
    end

    let(:scroll_registers) { instance_double(Ruby::Nes::Ppu::ScrollRegisters) }
    let(:fetcher) { instance_double(Ruby::Nes::Ppu::BackgroundFetcher) }
    let(:picture) { instance_double(Ruby::Nes::Ppu::Picture) }
    let(:sprite_renderer) { instance_double(Ruby::Nes::Ppu::SpriteRenderer) }
    let(:multiplexer) { instance_double(Ruby::Nes::Ppu::PriorityMultiplexer) }
    let(:schedule) { instance_double(Ruby::Nes::Ppu::RenderSchedule, :rendering_enabled= => nil) }

    it 'tells the schedule' do
      renderer.rendering_enabled = true
      expect(schedule).to have_received(:rendering_enabled=).with(true)
    end
  end

  describe '#frame_buffer' do
    subject(:renderer) { described_class.new(scroll_registers:, fetcher:, picture:, sprite_renderer:, multiplexer:) }

    let(:scroll_registers) { instance_double(Ruby::Nes::Ppu::ScrollRegisters) }
    let(:fetcher) { instance_double(Ruby::Nes::Ppu::BackgroundFetcher) }
    let(:picture) { instance_double(Ruby::Nes::Ppu::Picture, frame_buffer: [0x0F] * 4) }
    let(:sprite_renderer) { instance_double(Ruby::Nes::Ppu::SpriteRenderer) }
    let(:multiplexer) { instance_double(Ruby::Nes::Ppu::PriorityMultiplexer) }

    it "is the picture's" do
      expect(renderer.frame_buffer).to eq([0x0F] * 4)
    end
  end
end
