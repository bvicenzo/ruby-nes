# frozen_string_literal: true

# The renderer runs, on each dot, the steps the schedule gives (plan 13), as a per-dot pipeline (plan 25, decision 7).
# It owns the background's shift registers (https://www.nesdev.org/wiki/PPU_rendering): 16 bits each, two of pattern and
# two of attribute; a reload puts the fetched tile's pattern bytes and its palette's two bits, each repeated 8 times, in
# the low byte behind the tile on screen, and every shift moves them left one bit; the pixel is the 4 bits at bit 15 -
# fine X, palette high and low then pattern high and low. It draws at x = dot - 1 of the scanline (plan 13, decision 5):
# a background pixel whose pattern value (bits 1-0) is 0 is transparent, and each layer shows from its first visible
# column on (PPUMASK bits 1-4, LayerVisibility). Where only one layer is opaque its entry is drawn, a sprite's without
# SpriteLine's priority and sprite 0 marks; where both are, the priority multiplexer decides and checks the sprite 0 hit
# (https://www.nesdev.org/wiki/PPU_sprite_priority), and only then is it asked. It also runs the forced blank, the
# fetches and the v updates, hands the sprite steps to the sprite renderer, and passes the PPUCTRL and PPUMASK settings
# the Ppu tells it to the part that uses each.
RSpec.describe Ruby::Nes::Ppu::Renderer do
  describe '#run_dot' do
    let(:scroll_registers) do
      instance_double(
        Ruby::Nes::Ppu::ScrollRegisters,
        fine_x: 0,
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
    let(:sprite_line) { Ruby::Nes::Ppu::SpriteLine.new }
    let(:sprite_renderer) { instance_double(Ruby::Nes::Ppu::SpriteRenderer, line_entries: sprite_line.entries) }
    let(:multiplexer) { instance_double(Ruby::Nes::Ppu::PriorityMultiplexer, palette_entry: 0x15) }

    context 'when the dot has no step' do
      subject(:renderer) do
        described_class.new(scroll_registers:, fetcher:, picture:, sprite_renderer:, multiplexer:, schedule:)
      end

      let(:schedule) { instance_double(Ruby::Nes::Ppu::RenderSchedule, steps: 0) }

      before { renderer.run_dot(250, 300) }

      it 'touches nothing', :aggregate_failures do
        expect(picture).not_to have_received(:draw)
        expect(picture).not_to have_received(:draw_forced_blank)
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

    # Each tile below is reloaded, then shifted 8 times onto the screen, before the dot drawn.
    context 'when the dot reloads the shifters' do
      subject(:renderer) do
        described_class.new(
          scroll_registers:,
          fetcher:,
          picture:,
          sprite_renderer:,
          multiplexer:,
          schedule:,
          background_visibility:,
          sprite_visibility:
        )
      end

      let(:schedule) { instance_double(Ruby::Nes::Ppu::RenderSchedule) }
      let(:background_visibility) { Ruby::Nes::Ppu::LayerVisibility.new(enabled: true, left_columns_shown: true) }
      let(:sprite_visibility) { Ruby::Nes::Ppu::LayerVisibility.new(enabled: true, left_columns_shown: true) }

      before do
        allow(schedule).to receive(:steps).and_return(
          Ruby::Nes::Ppu::RenderSchedule::RELOAD,
          *Array.new(8, Ruby::Nes::Ppu::RenderSchedule::SHIFT),
          Ruby::Nes::Ppu::RenderSchedule::RELOAD,
          Ruby::Nes::Ppu::RenderSchedule::PIXEL,
          *Array.new(8, Ruby::Nes::Ppu::RenderSchedule::SHIFT),
          Ruby::Nes::Ppu::RenderSchedule::PIXEL
        )
        allow(fetcher).to receive(:pattern_low).and_return(0x80, 0x00)
        allow(fetcher).to receive(:pattern_high).and_return(0x00, 0x80)
        allow(fetcher).to receive(:palette).and_return(0b01, 0b10)
        20.times { renderer.run_dot(100, 1) }
      end

      it(
        "puts the fetched tile behind the one on screen, the palette's two bits spread over its 8 pixels",
        :aggregate_failures
      ) do
        expect(picture).to have_received(:draw).with(0, 100, 0b01_01).ordered
        expect(picture).to have_received(:draw).with(0, 100, 0b10_10).ordered
      end
    end

    context 'when the dot shifts' do
      subject(:renderer) do
        described_class.new(
          scroll_registers:,
          fetcher:,
          picture:,
          sprite_renderer:,
          multiplexer:,
          schedule:,
          background_visibility:,
          sprite_visibility:
        )
      end

      let(:schedule) { instance_double(Ruby::Nes::Ppu::RenderSchedule) }
      let(:background_visibility) { Ruby::Nes::Ppu::LayerVisibility.new(enabled: true, left_columns_shown: true) }
      let(:sprite_visibility) { Ruby::Nes::Ppu::LayerVisibility.new(enabled: true, left_columns_shown: true) }

      before do
        allow(schedule).to receive(:steps).and_return(
          Ruby::Nes::Ppu::RenderSchedule::RELOAD,
          *Array.new(9, Ruby::Nes::Ppu::RenderSchedule::SHIFT),
          Ruby::Nes::Ppu::RenderSchedule::PIXEL
        )
        allow(fetcher).to receive_messages(pattern_low: 0b0100_0000, pattern_high: 0x00, palette: 0b00)
        10.times { renderer.run_dot(100, 0) }
        renderer.run_dot(100, 1)
      end

      it 'brings the next pixel under fine X' do
        expect(picture).to have_received(:draw).with(0, 100, 0b00_01)
      end
    end

    context 'when the dot draws a pixel and shifts' do
      subject(:renderer) do
        described_class.new(
          scroll_registers:,
          fetcher:,
          picture:,
          sprite_renderer:,
          multiplexer:,
          schedule:,
          background_visibility:,
          sprite_visibility:
        )
      end

      let(:schedule) { instance_double(Ruby::Nes::Ppu::RenderSchedule) }
      let(:background_visibility) { Ruby::Nes::Ppu::LayerVisibility.new(enabled: true, left_columns_shown: true) }
      let(:sprite_visibility) { Ruby::Nes::Ppu::LayerVisibility.new(enabled: true, left_columns_shown: true) }

      before do
        allow(schedule).to receive(:steps).and_return(
          Ruby::Nes::Ppu::RenderSchedule::RELOAD,
          *Array.new(8, Ruby::Nes::Ppu::RenderSchedule::SHIFT),
          Ruby::Nes::Ppu::RenderSchedule::PIXEL | Ruby::Nes::Ppu::RenderSchedule::SHIFT
        )
        allow(fetcher).to receive_messages(pattern_low: 0b1000_0000, pattern_high: 0x00, palette: 0b00)
        9.times { renderer.run_dot(100, 0) }
        renderer.run_dot(100, 1)
      end

      it 'draws before shifting' do
        expect(picture).to have_received(:draw).with(0, 100, 0b00_01)
      end
    end

    context 'when the dot draws a pixel' do
      subject(:renderer) do
        described_class.new(
          scroll_registers:,
          fetcher:,
          picture:,
          sprite_renderer:,
          multiplexer:,
          schedule:,
          background_visibility:,
          sprite_visibility:
        )
      end

      let(:schedule) { instance_double(Ruby::Nes::Ppu::RenderSchedule) }

      before do
        allow(schedule).to receive(:steps).and_return(
          Ruby::Nes::Ppu::RenderSchedule::RELOAD,
          *Array.new(8, Ruby::Nes::Ppu::RenderSchedule::SHIFT),
          Ruby::Nes::Ppu::RenderSchedule::PIXEL
        )
      end

      # The tile on screen: pattern low 1000 0000 and high 0000 0001, palette 01, so its leftmost pixel is palette 01
      # with pattern 01, and its rightmost palette 01 with pattern 10.
      context 'and fine X is 0' do
        let(:background_visibility) { Ruby::Nes::Ppu::LayerVisibility.new(enabled: true, left_columns_shown: true) }
        let(:sprite_visibility) { Ruby::Nes::Ppu::LayerVisibility.new(enabled: true, left_columns_shown: true) }

        before do
          allow(fetcher).to receive_messages(pattern_low: 0b1000_0000, pattern_high: 0b0000_0001, palette: 0b01)
          9.times { renderer.run_dot(100, 0) }
          renderer.run_dot(100, 1)
        end

        it 'draws the leftmost pixel of the tile on screen, palette and pattern bits together' do
          expect(picture).to have_received(:draw).with(0, 100, 0b01_01)
        end
      end

      context 'and fine X is 7' do
        let(:background_visibility) { Ruby::Nes::Ppu::LayerVisibility.new(enabled: true, left_columns_shown: true) }
        let(:sprite_visibility) { Ruby::Nes::Ppu::LayerVisibility.new(enabled: true, left_columns_shown: true) }

        before do
          allow(scroll_registers).to receive(:fine_x).and_return(7)
          allow(fetcher).to receive_messages(pattern_low: 0b1000_0000, pattern_high: 0b0000_0001, palette: 0b01)
          9.times { renderer.run_dot(100, 0) }
          renderer.run_dot(100, 1)
        end

        it 'draws the rightmost pixel of the tile on screen' do
          expect(picture).to have_received(:draw).with(0, 100, 0b01_10)
        end
      end

      # The background tile's pixel is palette 10 with pattern 01 (entry $09) when opaque; the sprite placed at column 0
      # is palette 7 with pattern 01 (entry $1D), behind the background and sprite 0 ($7D in the line).
      context 'and the background pixel is transparent' do
        let(:background_visibility) { Ruby::Nes::Ppu::LayerVisibility.new(enabled: true, left_columns_shown: true) }

        context 'and the sprite entry is empty' do
          let(:sprite_visibility) { Ruby::Nes::Ppu::LayerVisibility.new(enabled: true, left_columns_shown: true) }

          before do
            allow(fetcher).to receive_messages(pattern_low: 0x00, pattern_high: 0x00, palette: 0b10)
            9.times { renderer.run_dot(100, 0) }
            renderer.run_dot(100, 1)
          end

          it 'draws the backdrop entry' do
            expect(picture).to have_received(:draw).with(0, 100, 0x00)
          end
        end

        context 'and the sprite pixel is left of its first visible column' do
          let(:sprite_visibility) { Ruby::Nes::Ppu::LayerVisibility.new(enabled: true, left_columns_shown: false) }

          before do
            allow(fetcher).to receive_messages(pattern_low: 0x00, pattern_high: 0x00, palette: 0b10)
            sprite_line.place(0, 0b1000_0000, 0b0000_0000, 0x23, true)
            9.times { renderer.run_dot(100, 0) }
            renderer.run_dot(100, 1)
          end

          it 'draws the backdrop entry' do
            expect(picture).to have_received(:draw).with(0, 100, 0x00)
          end
        end

        context 'and the sprite pixel is at its first visible column' do
          let(:sprite_visibility) { Ruby::Nes::Ppu::LayerVisibility.new(enabled: true, left_columns_shown: true) }

          before do
            allow(fetcher).to receive_messages(pattern_low: 0x00, pattern_high: 0x00, palette: 0b10)
            sprite_line.place(0, 0b1000_0000, 0b0000_0000, 0x23, true)
            9.times { renderer.run_dot(100, 0) }
            renderer.run_dot(100, 1)
          end

          it "draws the sprite's entry without its marks, not asking the multiplexer", :aggregate_failures do
            expect(picture).to have_received(:draw).with(0, 100, 0x1D)
            expect(multiplexer).not_to have_received(:palette_entry)
          end
        end
      end

      context 'and the background pixel is opaque' do
        context 'but it is left of its first visible column' do
          let(:background_visibility) { Ruby::Nes::Ppu::LayerVisibility.new(enabled: true, left_columns_shown: false) }

          context 'and the sprite entry is empty' do
            let(:sprite_visibility) { Ruby::Nes::Ppu::LayerVisibility.new(enabled: true, left_columns_shown: true) }

            before do
              allow(fetcher).to receive_messages(pattern_low: 0xFF, pattern_high: 0x00, palette: 0b10)
              9.times { renderer.run_dot(100, 0) }
              renderer.run_dot(100, 1)
            end

            it 'draws the backdrop entry' do
              expect(picture).to have_received(:draw).with(0, 100, 0x00)
            end
          end

          context 'and the sprite pixel is left of its first visible column' do
            let(:sprite_visibility) { Ruby::Nes::Ppu::LayerVisibility.new(enabled: true, left_columns_shown: false) }

            before do
              allow(fetcher).to receive_messages(pattern_low: 0xFF, pattern_high: 0x00, palette: 0b10)
              sprite_line.place(0, 0b1000_0000, 0b0000_0000, 0x23, true)
              9.times { renderer.run_dot(100, 0) }
              renderer.run_dot(100, 1)
            end

            it 'draws the backdrop entry' do
              expect(picture).to have_received(:draw).with(0, 100, 0x00)
            end
          end

          context 'and the sprite pixel is at its first visible column' do
            let(:sprite_visibility) { Ruby::Nes::Ppu::LayerVisibility.new(enabled: true, left_columns_shown: true) }

            before do
              allow(fetcher).to receive_messages(pattern_low: 0xFF, pattern_high: 0x00, palette: 0b10)
              sprite_line.place(0, 0b1000_0000, 0b0000_0000, 0x23, true)
              9.times { renderer.run_dot(100, 0) }
              renderer.run_dot(100, 1)
            end

            it "draws the sprite's palette entry, without asking the multiplexer", :aggregate_failures do
              expect(picture).to have_received(:draw).with(0, 100, 0x1D)
              expect(multiplexer).not_to have_received(:palette_entry)
            end
          end
        end

        context 'and it is at its first visible column' do
          let(:background_visibility) { Ruby::Nes::Ppu::LayerVisibility.new(enabled: true, left_columns_shown: true) }

          context 'and the sprite entry is empty' do
            let(:sprite_visibility) { Ruby::Nes::Ppu::LayerVisibility.new(enabled: true, left_columns_shown: true) }

            before do
              allow(fetcher).to receive_messages(pattern_low: 0xFF, pattern_high: 0x00, palette: 0b10)
              9.times { renderer.run_dot(100, 0) }
              renderer.run_dot(100, 1)
            end

            it 'draws the background entry' do
              expect(picture).to have_received(:draw).with(0, 100, 0x09)
            end
          end

          context 'and the sprite pixel is left of its first visible column' do
            let(:sprite_visibility) { Ruby::Nes::Ppu::LayerVisibility.new(enabled: true, left_columns_shown: false) }

            before do
              allow(fetcher).to receive_messages(pattern_low: 0xFF, pattern_high: 0x00, palette: 0b10)
              sprite_line.place(0, 0b1000_0000, 0b0000_0000, 0x23, true)
              9.times { renderer.run_dot(100, 0) }
              renderer.run_dot(100, 1)
            end

            it 'draws the background entry, without asking the multiplexer', :aggregate_failures do
              expect(picture).to have_received(:draw).with(0, 100, 0x09)
              expect(multiplexer).not_to have_received(:palette_entry)
            end
          end

          context 'and the sprite pixel is at its first visible column' do
            let(:sprite_visibility) { Ruby::Nes::Ppu::LayerVisibility.new(enabled: true, left_columns_shown: true) }

            before do
              allow(fetcher).to receive_messages(pattern_low: 0xFF, pattern_high: 0x00, palette: 0b10)
              sprite_line.place(0, 0b1000_0000, 0b0000_0000, 0x23, true)
              9.times { renderer.run_dot(100, 0) }
              renderer.run_dot(100, 1)
            end

            it "draws the multiplexer's entry for both", :aggregate_failures do
              expect(picture).to have_received(:draw).with(0, 100, 0x15)
              expect(multiplexer).to have_received(:palette_entry).with(0, 0x09, 0x7D)
            end
          end
        end
      end
    end

    context 'when the dot draws a forced blank pixel' do
      subject(:renderer) do
        described_class.new(scroll_registers:, fetcher:, picture:, sprite_renderer:, multiplexer:, schedule:)
      end

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

    context 'when the dot fetches the nametable byte' do
      subject(:renderer) do
        described_class.new(scroll_registers:, fetcher:, picture:, sprite_renderer:, multiplexer:, schedule:)
      end

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
      subject(:renderer) do
        described_class.new(scroll_registers:, fetcher:, picture:, sprite_renderer:, multiplexer:, schedule:)
      end

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
      subject(:renderer) do
        described_class.new(scroll_registers:, fetcher:, picture:, sprite_renderer:, multiplexer:, schedule:)
      end

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
      subject(:renderer) do
        described_class.new(scroll_registers:, fetcher:, picture:, sprite_renderer:, multiplexer:, schedule:)
      end

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
      subject(:renderer) do
        described_class.new(scroll_registers:, fetcher:, picture:, sprite_renderer:, multiplexer:, schedule:)
      end

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
      subject(:renderer) do
        described_class.new(scroll_registers:, fetcher:, picture:, sprite_renderer:, multiplexer:, schedule:)
      end

      let(:schedule) do
        instance_double(Ruby::Nes::Ppu::RenderSchedule, steps: Ruby::Nes::Ppu::RenderSchedule::INCREMENT_Y)
      end

      before { renderer.run_dot(0, 256) }

      it 'increments it in v' do
        expect(scroll_registers).to have_received(:increment_y)
      end
    end

    context 'when the dot copies the horizontal position' do
      subject(:renderer) do
        described_class.new(scroll_registers:, fetcher:, picture:, sprite_renderer:, multiplexer:, schedule:)
      end

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
      subject(:renderer) do
        described_class.new(scroll_registers:, fetcher:, picture:, sprite_renderer:, multiplexer:, schedule:)
      end

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
      subject(:renderer) do
        described_class.new(scroll_registers:, fetcher:, picture:, sprite_renderer:, multiplexer:, schedule:)
      end

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
  end

  describe '#pattern_table=' do
    subject(:renderer) { described_class.new(scroll_registers:, fetcher:, picture:, sprite_renderer:, multiplexer:) }

    let(:scroll_registers) { instance_double(Ruby::Nes::Ppu::ScrollRegisters) }
    let(:fetcher) { instance_double(Ruby::Nes::Ppu::BackgroundFetcher, :pattern_table= => nil) }
    let(:picture) { instance_double(Ruby::Nes::Ppu::Picture) }
    let(:sprite_renderer) { instance_double(Ruby::Nes::Ppu::SpriteRenderer, line_entries: []) }
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
    let(:sprite_renderer) { instance_double(Ruby::Nes::Ppu::SpriteRenderer, line_entries: []) }
    let(:multiplexer) { instance_double(Ruby::Nes::Ppu::PriorityMultiplexer) }

    it 'tells the picture' do
      renderer.greyscale = true
      expect(picture).to have_received(:greyscale=).with(true)
    end
  end

  describe '#emphasis=' do
    subject(:renderer) { described_class.new(scroll_registers:, fetcher:, picture:, sprite_renderer:, multiplexer:) }

    let(:scroll_registers) { instance_double(Ruby::Nes::Ppu::ScrollRegisters) }
    let(:fetcher) { instance_double(Ruby::Nes::Ppu::BackgroundFetcher) }
    let(:picture) { instance_double(Ruby::Nes::Ppu::Picture, :emphasis= => nil) }
    let(:sprite_renderer) { instance_double(Ruby::Nes::Ppu::SpriteRenderer, line_entries: []) }
    let(:multiplexer) { instance_double(Ruby::Nes::Ppu::PriorityMultiplexer) }

    it 'tells the picture' do
      renderer.emphasis = 0xA0
      expect(picture).to have_received(:emphasis=).with(0xA0)
    end
  end

  describe '#complete_picture' do
    subject(:renderer) { described_class.new(scroll_registers:, fetcher:, picture:, sprite_renderer:, multiplexer:) }

    let(:scroll_registers) { instance_double(Ruby::Nes::Ppu::ScrollRegisters) }
    let(:fetcher) { instance_double(Ruby::Nes::Ppu::BackgroundFetcher) }
    let(:picture) { instance_double(Ruby::Nes::Ppu::Picture, complete_frame: nil) }
    let(:sprite_renderer) { instance_double(Ruby::Nes::Ppu::SpriteRenderer, line_entries: []) }
    let(:multiplexer) { instance_double(Ruby::Nes::Ppu::PriorityMultiplexer) }

    it 'tells the picture to complete the frame' do
      renderer.complete_picture
      expect(picture).to have_received(:complete_frame).once
    end
  end

  describe '#background_enabled=' do
    subject(:renderer) do
      described_class.new(scroll_registers:, fetcher:, picture:, sprite_renderer:, multiplexer:, background_visibility:)
    end

    let(:scroll_registers) { instance_double(Ruby::Nes::Ppu::ScrollRegisters) }
    let(:fetcher) { instance_double(Ruby::Nes::Ppu::BackgroundFetcher) }
    let(:picture) { instance_double(Ruby::Nes::Ppu::Picture) }
    let(:sprite_renderer) { instance_double(Ruby::Nes::Ppu::SpriteRenderer, line_entries: []) }
    let(:multiplexer) { instance_double(Ruby::Nes::Ppu::PriorityMultiplexer) }
    let(:background_visibility) { instance_double(Ruby::Nes::Ppu::LayerVisibility, :enabled= => nil) }

    it 'tells the visibility' do
      renderer.background_enabled = true
      expect(background_visibility).to have_received(:enabled=).with(true)
    end
  end

  describe '#background_left_columns_shown=' do
    subject(:renderer) do
      described_class.new(scroll_registers:, fetcher:, picture:, sprite_renderer:, multiplexer:, background_visibility:)
    end

    let(:scroll_registers) { instance_double(Ruby::Nes::Ppu::ScrollRegisters) }
    let(:fetcher) { instance_double(Ruby::Nes::Ppu::BackgroundFetcher) }
    let(:picture) { instance_double(Ruby::Nes::Ppu::Picture) }
    let(:sprite_renderer) { instance_double(Ruby::Nes::Ppu::SpriteRenderer, line_entries: []) }
    let(:multiplexer) { instance_double(Ruby::Nes::Ppu::PriorityMultiplexer) }
    let(:background_visibility) { instance_double(Ruby::Nes::Ppu::LayerVisibility, :left_columns_shown= => nil) }

    it 'tells the visibility' do
      renderer.background_left_columns_shown = true
      expect(background_visibility).to have_received(:left_columns_shown=).with(true)
    end
  end

  describe '#sprites_enabled=' do
    subject(:renderer) do
      described_class.new(scroll_registers:, fetcher:, picture:, sprite_renderer:, multiplexer:, sprite_visibility:)
    end

    let(:scroll_registers) { instance_double(Ruby::Nes::Ppu::ScrollRegisters) }
    let(:fetcher) { instance_double(Ruby::Nes::Ppu::BackgroundFetcher) }
    let(:picture) { instance_double(Ruby::Nes::Ppu::Picture) }
    let(:sprite_renderer) { instance_double(Ruby::Nes::Ppu::SpriteRenderer, line_entries: []) }
    let(:multiplexer) { instance_double(Ruby::Nes::Ppu::PriorityMultiplexer) }
    let(:sprite_visibility) { instance_double(Ruby::Nes::Ppu::LayerVisibility, :enabled= => nil) }

    it "tells the sprites' visibility" do
      renderer.sprites_enabled = true
      expect(sprite_visibility).to have_received(:enabled=).with(true)
    end
  end

  describe '#sprite_left_columns_shown=' do
    subject(:renderer) do
      described_class.new(scroll_registers:, fetcher:, picture:, sprite_renderer:, multiplexer:, sprite_visibility:)
    end

    let(:scroll_registers) { instance_double(Ruby::Nes::Ppu::ScrollRegisters) }
    let(:fetcher) { instance_double(Ruby::Nes::Ppu::BackgroundFetcher) }
    let(:picture) { instance_double(Ruby::Nes::Ppu::Picture) }
    let(:sprite_renderer) { instance_double(Ruby::Nes::Ppu::SpriteRenderer, line_entries: []) }
    let(:multiplexer) { instance_double(Ruby::Nes::Ppu::PriorityMultiplexer) }
    let(:sprite_visibility) { instance_double(Ruby::Nes::Ppu::LayerVisibility, :left_columns_shown= => nil) }

    it "tells the sprites' visibility" do
      renderer.sprite_left_columns_shown = true
      expect(sprite_visibility).to have_received(:left_columns_shown=).with(true)
    end
  end

  describe '#rendering_enabled=' do
    subject(:renderer) do
      described_class.new(scroll_registers:, fetcher:, picture:, sprite_renderer:, multiplexer:, schedule:)
    end

    let(:scroll_registers) { instance_double(Ruby::Nes::Ppu::ScrollRegisters) }
    let(:fetcher) { instance_double(Ruby::Nes::Ppu::BackgroundFetcher) }
    let(:picture) { instance_double(Ruby::Nes::Ppu::Picture) }
    let(:sprite_renderer) { instance_double(Ruby::Nes::Ppu::SpriteRenderer, line_entries: []) }
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
    let(:sprite_renderer) { instance_double(Ruby::Nes::Ppu::SpriteRenderer, line_entries: []) }
    let(:multiplexer) { instance_double(Ruby::Nes::Ppu::PriorityMultiplexer) }

    it "is the picture's" do
      expect(renderer.frame_buffer).to eq([0x0F] * 4)
    end
  end
end
