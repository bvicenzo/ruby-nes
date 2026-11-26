# frozen_string_literal: true

# A smoke test of the raylib backend (plan 17, decision 4; plan 18; plan 36): little assertion on the library's calls,
# only that a hidden window opens, hands extra gamepad mappings to raylib, names raylib's keys and gamepad buttons for
# the config file, takes a frame and audio, draws a message and drops its audio (plan 35), and closes. Its decisions are
# specified in its collaborators. Skipped when the optional `frontends` group is not installed.
RSpec.describe 'Ruby::Nes::Frontends::Raylib', frontend_library: 'ruby/nes/frontends/raylib' do
  describe 'KEY_CODES' do
    it "names raylib's keys as the config file does" do
      expect(Ruby::Nes::Frontends::Raylib::KEY_CODES).to include('right_shift' => 344, 'enter' => 257, 'x' => 88)
    end
  end

  describe 'GAMEPAD_BUTTON_CODES' do
    it "names raylib's gamepad buttons as the config file does", :aggregate_failures do
      expect(Ruby::Nes::Frontends::Raylib::GAMEPAD_BUTTON_CODES)
        .to include('right_face_right' => 6, 'middle_right' => 15, 'left_face_up' => 1)
      expect(Ruby::Nes::Frontends::Raylib::GAMEPAD_BUTTON_CODES).not_to have_key('unknown')
    end
  end

  describe '.new' do
    context 'when gamepad mappings are given' do
      let(:gamepad_mappings) do
        '03000000790000001100000010010000,Retrolink SNES Controller,a:b2,b:b1,back:b8,dpdown:+a1,dpleft:-a0,' \
          'dpright:+a0,dpup:-a1,leftshoulder:b4,rightshoulder:b5,start:b9,x:b3,y:b0,platform:Linux,'
      end

      before { allow(Raylib).to receive(:SetGamepadMappings).and_call_original }

      it 'hands them to raylib' do
        frontend = Ruby::Nes::Frontends::Raylib.new(hidden: true, gamepad_mappings:)

        expect(Raylib).to have_received(:SetGamepadMappings).with(gamepad_mappings)
      ensure
        frontend&.close
      end
    end
  end

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

  describe '#paused?' do
    subject(:frontend) { Ruby::Nes::Frontends::Raylib.new(hidden: true) }

    after { frontend.close }

    context 'when no key is pressed' do
      it 'is false' do
        expect(frontend).not_to be_paused
      end
    end
  end

  describe '#reset_requested?' do
    subject(:frontend) { Ruby::Nes::Frontends::Raylib.new(hidden: true) }

    after { frontend.close }

    context 'when no key is pressed' do
      it 'is false' do
        expect(frontend).not_to be_reset_requested
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

  describe '#state_action' do
    subject(:frontend) { Ruby::Nes::Frontends::Raylib.new(hidden: true) }

    after { frontend.close }

    context 'when no key is pressed' do
      it 'is nil' do
        expect(frontend.state_action).to be_nil
      end
    end
  end

  describe '#notify' do
    subject(:frontend) { Ruby::Nes::Frontends::Raylib.new(hidden: true) }

    before { allow(Raylib).to receive(:DrawText).and_call_original }

    after { frontend.close }

    it 'draws the message over the next frame' do
      frontend.notify('State 3 saved')
      frontend.present(Array.new(Ruby::Nes::Ppu::Picture::WIDTH * Ruby::Nes::Ppu::Picture::HEIGHT, 0x16))

      expect(Raylib).to have_received(:DrawText).with('State 3 saved', any_args)
    end
  end

  describe '#discard_audio' do
    subject(:frontend) { Ruby::Nes::Frontends::Raylib.new(hidden: true) }

    after { frontend.close }

    it 'takes the order to drop the samples queued' do
      frontend.queue_audio(Array.new(Ruby::Nes::Frontends::Raylib::SAMPLES_PER_FRAME * 3, 1000))

      expect { frontend.discard_audio }.not_to raise_error
    end
  end

  describe '#closed?' do
    subject(:frontend) { Ruby::Nes::Frontends::Raylib.new(hidden: true) }

    after { frontend.close }

    context 'when the window is open' do
      it 'is false' do
        expect(frontend).not_to be_closed
      end
    end
  end

  describe '#next_screen' do
    subject(:frontend) { Ruby::Nes::Frontends::Raylib.new(hidden: true) }

    after { frontend.close }

    it 'takes the order to start over' do
      frontend.queue_audio(Array.new(Ruby::Nes::Frontends::Raylib::SAMPLES_PER_FRAME * 3, 1000))

      expect { frontend.next_screen }.not_to raise_error
    end
  end

  describe '#queue_silence' do
    subject(:frontend) { Ruby::Nes::Frontends::Raylib.new(hidden: true) }

    after { frontend.close }

    it 'takes the order to queue a frame of silence' do
      expect { frontend.queue_silence }.not_to raise_error
    end
  end
end
