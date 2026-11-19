# frozen_string_literal: true

# The background renderer runs, on each dot, the steps the schedule gives (plan 13): reloads the shifters with the
# fetched tile, draws the pixel the shifters hold under fine X at x = dot - 1 of the scanline (decision 5) as the
# visibility lets it through, or the forced blank, shifts, makes the fetches and updates v; a reload comes before the
# pixel it feeds, and the shift after it. It also passes the PPUCTRL and PPUMASK settings the Ppu tells it to the part
# that uses each.
RSpec.describe Ruby::Nes::Ppu::BackgroundRenderer do
  describe '#run_dot' do
    subject(:renderer) do
      described_class.new(scroll_registers:, fetcher:, picture:, schedule:, shifters:, visibility:)
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
    let(:visibility) { instance_double(Ruby::Nes::Ppu::BackgroundVisibility) }

    context 'when the dot has no step' do
      let(:schedule) { instance_double(Ruby::Nes::Ppu::BackgroundSchedule, steps: 0) }

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
        instance_double(Ruby::Nes::Ppu::BackgroundSchedule, steps: Ruby::Nes::Ppu::BackgroundSchedule::RELOAD)
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
        instance_double(Ruby::Nes::Ppu::BackgroundSchedule, steps: Ruby::Nes::Ppu::BackgroundSchedule::PIXEL)
      end

      before do
        allow(scroll_registers).to receive(:fine_x).and_return(3)
        allow(shifters).to receive(:pixel).with(3).and_return(0b10_01)
        allow(visibility).to receive(:palette_entry).with(9, 0b10_01).and_return(0b10_01)
        renderer.run_dot(239, 10)
      end

      it "draws at x dot - 1 of the scanline the visible entry of the shifters' pixel under fine X" do
        expect(picture).to have_received(:draw).with(9, 239, 0b10_01)
      end
    end

    context 'when the dot draws a forced blank pixel' do
      let(:schedule) do
        instance_double(
          Ruby::Nes::Ppu::BackgroundSchedule,
          steps: Ruby::Nes::Ppu::BackgroundSchedule::FORCED_BLANK_PIXEL
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
        instance_double(Ruby::Nes::Ppu::BackgroundSchedule, steps: Ruby::Nes::Ppu::BackgroundSchedule::SHIFT)
      end

      before { renderer.run_dot(261, 321) }

      it 'shifts the shifters' do
        expect(shifters).to have_received(:shift)
      end
    end

    context 'when the dot fetches the nametable byte' do
      let(:schedule) do
        instance_double(
          Ruby::Nes::Ppu::BackgroundSchedule,
          steps: Ruby::Nes::Ppu::BackgroundSchedule::FETCH_NAMETABLE
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
          Ruby::Nes::Ppu::BackgroundSchedule,
          steps: Ruby::Nes::Ppu::BackgroundSchedule::FETCH_ATTRIBUTE
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
          Ruby::Nes::Ppu::BackgroundSchedule,
          steps: Ruby::Nes::Ppu::BackgroundSchedule::FETCH_PATTERN_LOW
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
          Ruby::Nes::Ppu::BackgroundSchedule,
          steps: Ruby::Nes::Ppu::BackgroundSchedule::FETCH_PATTERN_HIGH
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
          Ruby::Nes::Ppu::BackgroundSchedule,
          steps: Ruby::Nes::Ppu::BackgroundSchedule::INCREMENT_COARSE_X
        )
      end

      before { renderer.run_dot(0, 8) }

      it 'increments it in v' do
        expect(scroll_registers).to have_received(:increment_coarse_x)
      end
    end

    context 'when the dot increments Y' do
      let(:schedule) do
        instance_double(Ruby::Nes::Ppu::BackgroundSchedule, steps: Ruby::Nes::Ppu::BackgroundSchedule::INCREMENT_Y)
      end

      before { renderer.run_dot(0, 256) }

      it 'increments it in v' do
        expect(scroll_registers).to have_received(:increment_y)
      end
    end

    context 'when the dot copies the horizontal position' do
      let(:schedule) do
        instance_double(
          Ruby::Nes::Ppu::BackgroundSchedule,
          steps: Ruby::Nes::Ppu::BackgroundSchedule::COPY_HORIZONTAL
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
          Ruby::Nes::Ppu::BackgroundSchedule,
          steps: Ruby::Nes::Ppu::BackgroundSchedule::COPY_VERTICAL
        )
      end

      before { renderer.run_dot(261, 280) }

      it 'copies it from t to v' do
        expect(scroll_registers).to have_received(:copy_vertical_position)
      end
    end

    context 'when the dot reloads, draws a pixel and shifts' do
      let(:schedule) do
        instance_double(
          Ruby::Nes::Ppu::BackgroundSchedule,
          steps: Ruby::Nes::Ppu::BackgroundSchedule::RELOAD |
            Ruby::Nes::Ppu::BackgroundSchedule::PIXEL |
            Ruby::Nes::Ppu::BackgroundSchedule::SHIFT
        )
      end

      before do
        allow(fetcher).to receive_messages(pattern_low: 0x5A, pattern_high: 0xC3, palette: 2)
        allow(scroll_registers).to receive(:fine_x).and_return(0)
        allow(shifters).to receive(:pixel).with(0).and_return(0b10_01)
        allow(visibility).to receive(:palette_entry).with(8, 0b10_01).and_return(0b10_01)
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
    subject(:renderer) { described_class.new(scroll_registers:, fetcher:, picture:) }

    let(:scroll_registers) { instance_double(Ruby::Nes::Ppu::ScrollRegisters) }
    let(:fetcher) { instance_double(Ruby::Nes::Ppu::BackgroundFetcher, :pattern_table= => nil) }
    let(:picture) { instance_double(Ruby::Nes::Ppu::Picture) }

    it 'tells the fetcher' do
      renderer.pattern_table = 0x1000
      expect(fetcher).to have_received(:pattern_table=).with(0x1000)
    end
  end

  describe '#greyscale=' do
    subject(:renderer) { described_class.new(scroll_registers:, fetcher:, picture:) }

    let(:scroll_registers) { instance_double(Ruby::Nes::Ppu::ScrollRegisters) }
    let(:fetcher) { instance_double(Ruby::Nes::Ppu::BackgroundFetcher) }
    let(:picture) { instance_double(Ruby::Nes::Ppu::Picture, :greyscale= => nil) }

    it 'tells the picture' do
      renderer.greyscale = true
      expect(picture).to have_received(:greyscale=).with(true)
    end
  end

  describe '#background_enabled=' do
    subject(:renderer) { described_class.new(scroll_registers:, fetcher:, picture:, visibility:) }

    let(:scroll_registers) { instance_double(Ruby::Nes::Ppu::ScrollRegisters) }
    let(:fetcher) { instance_double(Ruby::Nes::Ppu::BackgroundFetcher) }
    let(:picture) { instance_double(Ruby::Nes::Ppu::Picture) }
    let(:visibility) { instance_double(Ruby::Nes::Ppu::BackgroundVisibility, :background_enabled= => nil) }

    it 'tells the visibility' do
      renderer.background_enabled = true
      expect(visibility).to have_received(:background_enabled=).with(true)
    end
  end

  describe '#left_columns_shown=' do
    subject(:renderer) { described_class.new(scroll_registers:, fetcher:, picture:, visibility:) }

    let(:scroll_registers) { instance_double(Ruby::Nes::Ppu::ScrollRegisters) }
    let(:fetcher) { instance_double(Ruby::Nes::Ppu::BackgroundFetcher) }
    let(:picture) { instance_double(Ruby::Nes::Ppu::Picture) }
    let(:visibility) { instance_double(Ruby::Nes::Ppu::BackgroundVisibility, :left_columns_shown= => nil) }

    it 'tells the visibility' do
      renderer.left_columns_shown = true
      expect(visibility).to have_received(:left_columns_shown=).with(true)
    end
  end

  describe '#rendering_enabled=' do
    subject(:renderer) { described_class.new(scroll_registers:, fetcher:, picture:, schedule:) }

    let(:scroll_registers) { instance_double(Ruby::Nes::Ppu::ScrollRegisters) }
    let(:fetcher) { instance_double(Ruby::Nes::Ppu::BackgroundFetcher) }
    let(:picture) { instance_double(Ruby::Nes::Ppu::Picture) }
    let(:schedule) { instance_double(Ruby::Nes::Ppu::BackgroundSchedule, :rendering_enabled= => nil) }

    it 'tells the schedule' do
      renderer.rendering_enabled = true
      expect(schedule).to have_received(:rendering_enabled=).with(true)
    end
  end

  describe '#frame_buffer' do
    subject(:renderer) { described_class.new(scroll_registers:, fetcher:, picture:) }

    let(:scroll_registers) { instance_double(Ruby::Nes::Ppu::ScrollRegisters) }
    let(:fetcher) { instance_double(Ruby::Nes::Ppu::BackgroundFetcher) }
    let(:picture) { instance_double(Ruby::Nes::Ppu::Picture, frame_buffer: [0x0F] * 4) }

    it "is the picture's" do
      expect(renderer.frame_buffer).to eq([0x0F] * 4)
    end
  end
end
