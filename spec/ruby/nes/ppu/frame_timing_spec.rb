# frozen_string_literal: true

# NTSC frame timing (https://www.nesdev.org/wiki/PPU_frame_timing, https://www.nesdev.org/wiki/PPU_rendering):
# 262 scanlines of 341 dots (0-340); the VBlank flag is set at dot 1 of scanline 241 and cleared at dot 1 of the
# pre-render scanline 261. With rendering enabled, odd frames jump "directly from (339,261) ... to (0,0)"; "The PPU has
# an even/odd flag that is toggled every frame, regardless of whether rendering is enabled"; "Turning rendering on late
# causes the dot at the end of pre-render to never be skipped". "The PPU comes out of power and reset at the top of the
# picture" (https://www.nesdev.org/wiki/PPU_power_up_state).
RSpec.describe Ruby::Nes::Ppu::FrameTiming do
  describe '.new' do
    let(:events) { instance_double(Ruby::Nes::Ppu) }

    it 'starts at dot 0 of scanline 0, on frame 0, even' do
      frame_timing = described_class.new(events:)
      expect(frame_timing).to have_attributes(scanline: 0, dot: 0, frame_number: 0, odd_frame?: false)
    end
  end

  describe '#advance' do
    subject(:frame_timing) { described_class.new(events:, scanline:, dot:, odd_frame:, rendering_enabled:) }

    let(:events) do
      instance_double(Ruby::Nes::Ppu, vertical_blank_started: nil, vertical_blank_ended: nil, picture_completed: nil)
    end

    context 'when the position is dot 339 of the pre-render scanline' do
      let(:scanline) { 261 }
      let(:dot) { 339 }

      context 'and the frame is even' do
        let(:odd_frame) { false }

        context 'and rendering is disabled' do
          let(:rendering_enabled) { false }

          it 'moves to dot 340 of the pre-render scanline' do
            frame_timing.advance
            expect(frame_timing).to have_attributes(scanline: 261, dot: 340)
          end
        end

        context 'and rendering is enabled' do
          let(:rendering_enabled) { true }

          it 'moves to dot 340 of the pre-render scanline' do
            frame_timing.advance
            expect(frame_timing).to have_attributes(scanline: 261, dot: 340)
          end
        end
      end

      context 'and the frame is odd' do
        let(:odd_frame) { true }

        context 'but rendering is disabled' do
          let(:rendering_enabled) { false }

          it 'moves to dot 340 of the pre-render scanline' do
            frame_timing.advance
            expect(frame_timing).to have_attributes(scanline: 261, dot: 340)
          end
        end

        context 'and rendering is enabled' do
          let(:rendering_enabled) { true }

          it 'moves to dot 0 of scanline 0' do
            frame_timing.advance
            expect(frame_timing).to have_attributes(scanline: 0, dot: 0)
          end

          it 'counts a new frame' do
            expect { frame_timing.advance }.to change(frame_timing, :frame_number).from(0).to(1)
          end

          it 'makes the frame even' do
            expect { frame_timing.advance }.to change(frame_timing, :odd_frame?).from(true).to(false)
          end

          it 'tells the events nothing', :aggregate_failures do
            frame_timing.advance
            expect(events).not_to have_received(:vertical_blank_started)
            expect(events).not_to have_received(:vertical_blank_ended)
            expect(events).not_to have_received(:picture_completed)
          end
        end
      end
    end

    context 'when the position is the last dot of a scanline' do
      let(:dot) { 340 }

      # The last visible pixel is drawn at dot 256 of scanline 239: entering the post-render scanline 240 completes the
      # picture (plan 16, decision 1), whether it was rendered or drawn in forced blank.
      context 'and the scanline is the last visible one' do
        let(:scanline) { 239 }
        let(:odd_frame) { false }

        context 'and rendering is disabled' do
          let(:rendering_enabled) { false }

          it 'moves to dot 0 of the post-render scanline' do
            frame_timing.advance
            expect(frame_timing).to have_attributes(scanline: 240, dot: 0)
          end

          it 'keeps the frame number' do
            expect { frame_timing.advance }.not_to change(frame_timing, :frame_number)
          end

          it 'tells the events the picture is complete' do
            frame_timing.advance
            expect(events).to have_received(:picture_completed).once
          end
        end

        context 'and rendering is enabled' do
          let(:rendering_enabled) { true }

          it 'moves to dot 0 of the post-render scanline' do
            frame_timing.advance
            expect(frame_timing).to have_attributes(scanline: 240, dot: 0)
          end

          it 'keeps the frame number' do
            expect { frame_timing.advance }.not_to change(frame_timing, :frame_number)
          end

          it 'tells the events the picture is complete' do
            frame_timing.advance
            expect(events).to have_received(:picture_completed).once
          end
        end
      end

      context 'and the scanline is another one before the pre-render one' do
        let(:scanline) { 260 }
        let(:odd_frame) { false }
        let(:rendering_enabled) { false }

        it 'moves to dot 0 of the next scanline' do
          frame_timing.advance
          expect(frame_timing).to have_attributes(scanline: 261, dot: 0)
        end

        it 'keeps the frame number' do
          expect { frame_timing.advance }.not_to change(frame_timing, :frame_number)
        end

        it 'tells the events nothing', :aggregate_failures do
          frame_timing.advance
          expect(events).not_to have_received(:vertical_blank_started)
          expect(events).not_to have_received(:vertical_blank_ended)
          expect(events).not_to have_received(:picture_completed)
        end
      end

      context 'and the scanline is the pre-render one' do
        let(:scanline) { 261 }

        context 'and the frame is even' do
          let(:odd_frame) { false }
          let(:rendering_enabled) { false }

          it 'moves to dot 0 of scanline 0' do
            frame_timing.advance
            expect(frame_timing).to have_attributes(scanline: 0, dot: 0)
          end

          it 'counts a new frame' do
            expect { frame_timing.advance }.to change(frame_timing, :frame_number).from(0).to(1)
          end

          it 'tells the events nothing', :aggregate_failures do
            frame_timing.advance
            expect(events).not_to have_received(:vertical_blank_started)
            expect(events).not_to have_received(:vertical_blank_ended)
            expect(events).not_to have_received(:picture_completed)
          end

          it 'makes the frame odd' do
            expect { frame_timing.advance }.to change(frame_timing, :odd_frame?).from(false).to(true)
          end
        end

        context 'and the frame is odd' do
          let(:odd_frame) { true }
          let(:rendering_enabled) { true }

          it 'moves to dot 0 of scanline 0' do
            frame_timing.advance
            expect(frame_timing).to have_attributes(scanline: 0, dot: 0)
          end

          it 'counts a new frame' do
            expect { frame_timing.advance }.to change(frame_timing, :frame_number).from(0).to(1)
          end

          it 'tells the events nothing', :aggregate_failures do
            frame_timing.advance
            expect(events).not_to have_received(:vertical_blank_started)
            expect(events).not_to have_received(:vertical_blank_ended)
            expect(events).not_to have_received(:picture_completed)
          end

          it 'makes the frame even' do
            expect { frame_timing.advance }.to change(frame_timing, :odd_frame?).from(true).to(false)
          end
        end
      end
    end

    context 'when the position is any other dot' do
      let(:odd_frame) { false }
      let(:rendering_enabled) { false }

      context 'and the next dot is dot 1 of scanline 241' do
        context 'but the status was read on the current dot' do
          let(:scanline) { 241 }
          let(:dot) { 0 }

          before { frame_timing.status_read }

          it 'moves to that dot' do
            frame_timing.advance
            expect(frame_timing).to have_attributes(scanline: 241, dot: 1)
          end

          it 'tells the events nothing', :aggregate_failures do
            frame_timing.advance
            expect(events).not_to have_received(:vertical_blank_started)
            expect(events).not_to have_received(:vertical_blank_ended)
            expect(events).not_to have_received(:picture_completed)
          end
        end

        context 'and the status was read on the dot before' do
          let(:scanline) { 240 }
          let(:dot) { 340 }

          before do
            frame_timing.status_read
            frame_timing.advance
          end

          it 'tells the events that vertical blank started' do
            frame_timing.advance
            expect(events).to have_received(:vertical_blank_started).once
          end
        end

        context 'and the status was read on dot 0 of the scanline before' do
          let(:scanline) { 240 }
          let(:dot) { 0 }

          before do
            frame_timing.status_read
            341.times { frame_timing.advance }
          end

          it 'tells the events that vertical blank started' do
            frame_timing.advance
            expect(events).to have_received(:vertical_blank_started).once
          end
        end

        context 'and the status was read on dot 1 of scanline 241 a frame before' do
          let(:scanline) { 241 }
          let(:dot) { 1 }

          before do
            frame_timing.status_read
            89_341.times { frame_timing.advance }
          end

          it 'tells the events that vertical blank started' do
            frame_timing.advance
            expect(events).to have_received(:vertical_blank_started).once
          end
        end

        context 'and the status was not read' do
          let(:scanline) { 241 }
          let(:dot) { 0 }

          it 'moves to that dot' do
            frame_timing.advance
            expect(frame_timing).to have_attributes(scanline: 241, dot: 1)
          end

          it 'tells the events that vertical blank started', :aggregate_failures do
            frame_timing.advance
            expect(events).to have_received(:vertical_blank_started).once
            expect(events).not_to have_received(:vertical_blank_ended)
          end
        end
      end

      context 'and the next dot is dot 1 of the pre-render scanline' do
        let(:scanline) { 261 }
        let(:dot) { 0 }

        it 'moves to that dot' do
          frame_timing.advance
          expect(frame_timing).to have_attributes(scanline: 261, dot: 1)
        end

        it 'tells the events that vertical blank ended', :aggregate_failures do
          frame_timing.advance
          expect(events).to have_received(:vertical_blank_ended).once
          expect(events).not_to have_received(:vertical_blank_started)
        end
      end

      context 'and the next dot is another dot of scanline 241' do
        let(:scanline) { 241 }
        let(:dot) { 1 }

        it 'tells the events nothing', :aggregate_failures do
          frame_timing.advance
          expect(events).not_to have_received(:vertical_blank_started)
          expect(events).not_to have_received(:vertical_blank_ended)
          expect(events).not_to have_received(:picture_completed)
        end
      end

      context 'and the next dot is dot 1 of another scanline' do
        let(:scanline) { 240 }
        let(:dot) { 0 }

        it 'tells the events nothing', :aggregate_failures do
          frame_timing.advance
          expect(events).not_to have_received(:vertical_blank_started)
          expect(events).not_to have_received(:vertical_blank_ended)
          expect(events).not_to have_received(:picture_completed)
        end
      end
    end
  end

  describe '#reset' do
    context 'when no status read is waiting to cancel vertical blank' do
      subject(:frame_timing) { described_class.new(events:, scanline: 120, dot: 200, odd_frame: true, frame_number: 5) }

      let(:events) { instance_double(Ruby::Nes::Ppu) }

      it 'moves to dot 0 of scanline 0' do
        frame_timing.reset
        expect(frame_timing).to have_attributes(scanline: 0, dot: 0)
      end

      it 'makes the frame even' do
        expect { frame_timing.reset }.to change(frame_timing, :odd_frame?).from(true).to(false)
      end

      it 'keeps the frame number' do
        expect { frame_timing.reset }.not_to change(frame_timing, :frame_number).from(5)
      end
    end

    context 'when the status was just read on dot 0 of scanline 241' do
      subject(:frame_timing) { described_class.new(events:, scanline: 241, dot: 0) }

      let(:events) do
        instance_double(Ruby::Nes::Ppu, vertical_blank_started: nil, vertical_blank_ended: nil, picture_completed: nil)
      end

      before do
        frame_timing.status_read
        frame_timing.reset
      end

      it 'lets vertical blank start in the next frame' do
        82_182.times { frame_timing.advance }
        expect(events).to have_received(:vertical_blank_started).once
      end
    end
  end

  # PPUDATA's update of v changes "During rendering (on the pre-render line and the visible lines 0-239, provided
  # either background or sprite rendering is enabled)" (https://www.nesdev.org/wiki/PPU_scrolling).
  describe '#rendering_in_progress?' do
    let(:events) { instance_double(Ruby::Nes::Ppu) }

    context 'when rendering is disabled' do
      subject(:frame_timing) { described_class.new(events:, scanline: 120, rendering_enabled: false) }

      it 'is false' do
        expect(frame_timing).not_to be_rendering_in_progress
      end
    end

    context 'when rendering is enabled' do
      context 'and the scanline is the post-render one' do
        subject(:frame_timing) { described_class.new(events:, scanline: 240, rendering_enabled: true) }

        it 'is false' do
          expect(frame_timing).not_to be_rendering_in_progress
        end
      end

      context 'and the scanline is a VBlank one' do
        subject(:frame_timing) { described_class.new(events:, scanline: 260, rendering_enabled: true) }

        it 'is false' do
          expect(frame_timing).not_to be_rendering_in_progress
        end
      end

      context 'and the scanline is a visible one' do
        subject(:frame_timing) { described_class.new(events:, scanline: 239, rendering_enabled: true) }

        it 'is true' do
          expect(frame_timing).to be_rendering_in_progress
        end
      end

      context 'and the scanline is the pre-render one' do
        subject(:frame_timing) { described_class.new(events:, scanline: 261, rendering_enabled: true) }

        it 'is true' do
          expect(frame_timing).to be_rendering_in_progress
        end
      end
    end
  end
end
