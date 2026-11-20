# frozen_string_literal: true

# A smoke test of the raylib backend (plan 17, decision 4): no assertion on the library's calls, only that a hidden
# window opens, takes a frame and audio, and closes. Skipped when the optional `frontends` group is not installed.
RSpec.describe 'Ruby::Nes::Frontends::Raylib', frontend_library: 'ruby/nes/frontends/raylib' do
  describe '#running?' do
    subject(:frontend) { Ruby::Nes::Frontends::Raylib.new(hidden: true) }

    after { frontend.close }

    context 'when the window is open' do
      it 'is true' do
        expect(frontend).to be_running
      end
    end
  end

  describe '#button_states' do
    subject(:frontend) { Ruby::Nes::Frontends::Raylib.new(hidden: true) }

    after { frontend.close }

    context 'when no key is held' do
      it 'holds nothing on either controller' do
        expect(frontend.button_states).to eq([0, 0])
      end
    end
  end

  describe '#present' do
    subject(:frontend) { Ruby::Nes::Frontends::Raylib.new(hidden: true) }

    after { frontend.close }

    it 'draws a frame' do
      frame_buffer = Array.new(Ruby::Nes::Ppu::Picture::WIDTH * Ruby::Nes::Ppu::Picture::HEIGHT, 0x16)

      expect { frontend.present(frame_buffer) }.not_to raise_error
    end
  end

  describe '#queue_audio' do
    subject(:frontend) { Ruby::Nes::Frontends::Raylib.new(hidden: true) }

    after { frontend.close }

    it 'takes a frame of samples' do
      samples = Array.new(Ruby::Nes::Frontends::Raylib::SAMPLES_PER_FRAME, 1000)

      expect { frontend.queue_audio(samples) }.not_to raise_error
    end
  end
end
