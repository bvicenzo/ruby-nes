# frozen_string_literal: true

# The background's work on each dot (https://www.nesdev.org/wiki/PPU_rendering, https://www.nesdev.org/wiki/PPU_scrolling).
# On the visible (0-239) and pre-render (261) scanlines with rendering enabled: each tile's nametable, attribute, low
# and high pattern fetches take 2 dots each (dots 1-256 and 321-336, done on the first dot of each pair); "The
# shifters are reloaded during ticks 9, 17, 25, ..., 257" and with the two tiles of 321-336 (dots 329 and 337);
# coarse X increments at 8, 16, ..., 256, 328 and 336; Y at 256; the horizontal copy at 257; the vertical copy at
# 280-304 of the pre-render line. Visible lines draw dots 1-256 (x = dot - 1, plan 13 decision 5) and shift then; the
# shifts of 321-336 bring the next line's first two tiles in. With rendering disabled, visible lines draw the forced
# blank and nothing else happens. The garbage nametable fetches of 257-320 and 337-340 are not made (decision 6).
RSpec.describe Ruby::Nes::Ppu::BackgroundSchedule do
  describe '#steps' do
    context 'when rendering is disabled' do
      subject(:schedule) { described_class.new(rendering_enabled: false) }

      context 'and the scanline is visible' do
        context 'and the dot is 0' do
          it 'does nothing' do
            expect(schedule.steps(239, 0)).to eq(0)
          end
        end

        context 'and the dot is 1' do
          it 'draws a forced blank pixel' do
            expect(schedule.steps(239, 1)).to eq(described_class::FORCED_BLANK_PIXEL)
          end
        end

        context 'and the dot is 256' do
          it 'draws a forced blank pixel' do
            expect(schedule.steps(239, 256)).to eq(described_class::FORCED_BLANK_PIXEL)
          end
        end

        context 'and the dot is 257' do
          it 'does nothing' do
            expect(schedule.steps(239, 257)).to eq(0)
          end
        end
      end

      context 'and the scanline is the post-render one' do
        it 'does nothing' do
          expect(schedule.steps(240, 1)).to eq(0)
        end
      end

      context 'and the scanline is the pre-render one' do
        context 'and the dot is 1' do
          it 'does nothing' do
            expect(schedule.steps(261, 1)).to eq(0)
          end
        end

        context 'and the dot is 280' do
          it 'does nothing' do
            expect(schedule.steps(261, 280)).to eq(0)
          end
        end
      end
    end

    context 'when rendering is enabled' do
      subject(:schedule) { described_class.new(rendering_enabled: true) }

      context 'and the scanline is visible' do
        context 'and the dot is 0' do
          it 'does nothing' do
            expect(schedule.steps(239, 0)).to eq(0)
          end
        end

        context 'and the dot is 1, the first of a tile' do
          it 'draws a pixel, shifts and fetches the nametable byte' do
            expect(schedule.steps(239, 1)).to eq(
              described_class::PIXEL |
              described_class::SHIFT |
              described_class::FETCH_NAMETABLE
            )
          end
        end

        context 'and the dot is 2' do
          it 'draws a pixel and shifts' do
            expect(schedule.steps(239, 2)).to eq(described_class::PIXEL | described_class::SHIFT)
          end
        end

        context 'and the dot is 3' do
          it 'draws a pixel, shifts and fetches the attribute byte' do
            expect(schedule.steps(239, 3)).to eq(
              described_class::PIXEL |
              described_class::SHIFT |
              described_class::FETCH_ATTRIBUTE
            )
          end
        end

        context 'and the dot is 5' do
          it 'draws a pixel, shifts and fetches the low pattern byte' do
            expect(schedule.steps(239, 5)).to eq(
              described_class::PIXEL |
              described_class::SHIFT |
              described_class::FETCH_PATTERN_LOW
            )
          end
        end

        context 'and the dot is 7' do
          it 'draws a pixel, shifts and fetches the high pattern byte' do
            expect(schedule.steps(239, 7)).to eq(
              described_class::PIXEL |
              described_class::SHIFT |
              described_class::FETCH_PATTERN_HIGH
            )
          end
        end

        context 'and the dot is 8, the last of a tile' do
          it 'draws a pixel, shifts and increments coarse X' do
            expect(schedule.steps(239, 8)).to eq(
              described_class::PIXEL |
              described_class::SHIFT |
              described_class::INCREMENT_COARSE_X
            )
          end
        end

        context 'and the dot is 9, the first of the next tile' do
          it 'draws a pixel, reloads the shifters, shifts and fetches the nametable byte' do
            expect(schedule.steps(239, 9)).to eq(
              described_class::PIXEL |
              described_class::RELOAD |
              described_class::SHIFT |
              described_class::FETCH_NAMETABLE
            )
          end
        end

        context 'and the dot is 256, the last pixel' do
          it 'draws a pixel, shifts, increments coarse X and increments Y' do
            expect(schedule.steps(239, 256)).to eq(
              described_class::PIXEL |
              described_class::SHIFT |
              described_class::INCREMENT_COARSE_X |
              described_class::INCREMENT_Y
            )
          end
        end

        context 'and the dot is 257' do
          it 'reloads the shifters and copies the horizontal position' do
            expect(schedule.steps(239, 257)).to eq(described_class::RELOAD | described_class::COPY_HORIZONTAL)
          end
        end

        context 'and the dot is 258' do
          it 'does nothing' do
            expect(schedule.steps(239, 258)).to eq(0)
          end
        end

        context 'and the dot is 279' do
          it 'does nothing' do
            expect(schedule.steps(239, 279)).to eq(0)
          end
        end

        context 'and the dot is 280' do
          it 'does nothing' do
            expect(schedule.steps(239, 280)).to eq(0)
          end
        end

        context 'and the dot is 304' do
          it 'does nothing' do
            expect(schedule.steps(239, 304)).to eq(0)
          end
        end

        context 'and the dot is 305' do
          it 'does nothing' do
            expect(schedule.steps(239, 305)).to eq(0)
          end
        end

        context 'and the dot is 320' do
          it 'does nothing' do
            expect(schedule.steps(239, 320)).to eq(0)
          end
        end

        context "and the dot is 321, the first of the next line's first tile" do
          it 'shifts and fetches the nametable byte' do
            expect(schedule.steps(239, 321)).to eq(described_class::SHIFT | described_class::FETCH_NAMETABLE)
          end
        end

        context 'and the dot is 328' do
          it 'shifts and increments coarse X' do
            expect(schedule.steps(239, 328)).to eq(described_class::SHIFT | described_class::INCREMENT_COARSE_X)
          end
        end

        context "and the dot is 329, the first of the next line's second tile" do
          it 'reloads the shifters, shifts and fetches the nametable byte' do
            expect(schedule.steps(239, 329)).to eq(
              described_class::RELOAD |
              described_class::SHIFT |
              described_class::FETCH_NAMETABLE
            )
          end
        end

        context 'and the dot is 336' do
          it 'shifts and increments coarse X' do
            expect(schedule.steps(239, 336)).to eq(described_class::SHIFT | described_class::INCREMENT_COARSE_X)
          end
        end

        context 'and the dot is 337' do
          it 'reloads the shifters' do
            expect(schedule.steps(239, 337)).to eq(described_class::RELOAD)
          end
        end

        context 'and the dot is 338' do
          it 'does nothing' do
            expect(schedule.steps(239, 338)).to eq(0)
          end
        end
      end

      context 'and the scanline is the post-render one' do
        it 'does nothing' do
          expect(schedule.steps(240, 1)).to eq(0)
        end
      end

      context 'and the scanline is the last of VBlank' do
        it 'does nothing' do
          expect(schedule.steps(260, 1)).to eq(0)
        end
      end

      context 'and the scanline is the pre-render one' do
        context 'and the dot is 0' do
          it 'does nothing' do
            expect(schedule.steps(261, 0)).to eq(0)
          end
        end

        context 'and the dot is 1, the first of a tile' do
          it 'shifts and fetches the nametable byte' do
            expect(schedule.steps(261, 1)).to eq(described_class::SHIFT | described_class::FETCH_NAMETABLE)
          end
        end

        context 'and the dot is 2' do
          it 'shifts' do
            expect(schedule.steps(261, 2)).to eq(described_class::SHIFT)
          end
        end

        context 'and the dot is 3' do
          it 'shifts and fetches the attribute byte' do
            expect(schedule.steps(261, 3)).to eq(described_class::SHIFT | described_class::FETCH_ATTRIBUTE)
          end
        end

        context 'and the dot is 5' do
          it 'shifts and fetches the low pattern byte' do
            expect(schedule.steps(261, 5)).to eq(described_class::SHIFT | described_class::FETCH_PATTERN_LOW)
          end
        end

        context 'and the dot is 7' do
          it 'shifts and fetches the high pattern byte' do
            expect(schedule.steps(261, 7)).to eq(described_class::SHIFT | described_class::FETCH_PATTERN_HIGH)
          end
        end

        context 'and the dot is 8, the last of a tile' do
          it 'shifts and increments coarse X' do
            expect(schedule.steps(261, 8)).to eq(described_class::SHIFT | described_class::INCREMENT_COARSE_X)
          end
        end

        context 'and the dot is 9, the first of the next tile' do
          it 'reloads the shifters, shifts and fetches the nametable byte' do
            expect(schedule.steps(261, 9)).to eq(
              described_class::RELOAD |
              described_class::SHIFT |
              described_class::FETCH_NAMETABLE
            )
          end
        end

        context 'and the dot is 256, the last pixel' do
          it 'shifts, increments coarse X and increments Y' do
            expect(schedule.steps(261, 256)).to eq(
              described_class::SHIFT |
              described_class::INCREMENT_COARSE_X |
              described_class::INCREMENT_Y
            )
          end
        end

        context 'and the dot is 257' do
          it 'reloads the shifters and copies the horizontal position' do
            expect(schedule.steps(261, 257)).to eq(described_class::RELOAD | described_class::COPY_HORIZONTAL)
          end
        end

        context 'and the dot is 258' do
          it 'does nothing' do
            expect(schedule.steps(261, 258)).to eq(0)
          end
        end

        context 'and the dot is 279' do
          it 'does nothing' do
            expect(schedule.steps(261, 279)).to eq(0)
          end
        end

        context 'and the dot is 280' do
          it 'copies the vertical position' do
            expect(schedule.steps(261, 280)).to eq(described_class::COPY_VERTICAL)
          end
        end

        context 'and the dot is 304' do
          it 'copies the vertical position' do
            expect(schedule.steps(261, 304)).to eq(described_class::COPY_VERTICAL)
          end
        end

        context 'and the dot is 305' do
          it 'does nothing' do
            expect(schedule.steps(261, 305)).to eq(0)
          end
        end

        context 'and the dot is 320' do
          it 'does nothing' do
            expect(schedule.steps(261, 320)).to eq(0)
          end
        end

        context "and the dot is 321, the first of the next line's first tile" do
          it 'shifts and fetches the nametable byte' do
            expect(schedule.steps(261, 321)).to eq(described_class::SHIFT | described_class::FETCH_NAMETABLE)
          end
        end

        context 'and the dot is 328' do
          it 'shifts and increments coarse X' do
            expect(schedule.steps(261, 328)).to eq(described_class::SHIFT | described_class::INCREMENT_COARSE_X)
          end
        end

        context "and the dot is 329, the first of the next line's second tile" do
          it 'reloads the shifters, shifts and fetches the nametable byte' do
            expect(schedule.steps(261, 329)).to eq(
              described_class::RELOAD |
              described_class::SHIFT |
              described_class::FETCH_NAMETABLE
            )
          end
        end

        context 'and the dot is 336' do
          it 'shifts and increments coarse X' do
            expect(schedule.steps(261, 336)).to eq(described_class::SHIFT | described_class::INCREMENT_COARSE_X)
          end
        end

        context 'and the dot is 337' do
          it 'reloads the shifters' do
            expect(schedule.steps(261, 337)).to eq(described_class::RELOAD)
          end
        end

        context 'and the dot is 338' do
          it 'does nothing' do
            expect(schedule.steps(261, 338)).to eq(0)
          end
        end
      end
    end
  end

  describe '#rendering_enabled=' do
    context 'when rendering is turned on' do
      subject(:schedule) { described_class.new(rendering_enabled: false) }

      it 'schedules the rendering steps' do
        schedule.rendering_enabled = true
        expect(schedule.steps(0, 257)).to eq(described_class::RELOAD | described_class::COPY_HORIZONTAL)
      end
    end

    context 'when rendering is turned off' do
      subject(:schedule) { described_class.new(rendering_enabled: true) }

      it 'schedules the forced blank' do
        schedule.rendering_enabled = false
        expect(schedule.steps(0, 1)).to eq(described_class::FORCED_BLANK_PIXEL)
      end
    end
  end
end
