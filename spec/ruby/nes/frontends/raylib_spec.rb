# frozen_string_literal: true

# A smoke test of the raylib backend (plan 17, decision 4; plan 18; plan 36): little assertion on the library's calls,
# only that a hidden window opens, hands extra gamepad mappings to raylib, names raylib's keys and gamepad buttons for
# the config file, takes a frame and audio, draws a message and drops its audio (plan 35), ends its screen or the
# session and resumes from a menu (plan 38), and closes. Its decisions are
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

    context 'when the screen was left' do
      before { frontend.leave }

      context 'and no screen started since' do
        it 'is false, the window still open', :aggregate_failures do
          expect(frontend).not_to be_running
          expect(frontend).not_to be_closed
        end
      end

      context 'but the next screen started' do
        before { frontend.next_screen }

        it 'is true' do
          expect(frontend).to be_running
        end
      end
    end

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

    # The window opens first: it attaches the raylib library, which defines DrawText.
    before do
      frontend
      allow(Raylib).to receive(:DrawText).and_call_original
    end

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

    context 'when the player quit from a menu' do
      before { frontend.quit }

      it 'is true' do
        expect(frontend).to be_closed
      end
    end

    context 'when the window is open' do
      it 'is false' do
        expect(frontend).not_to be_closed
      end
    end
  end

  describe '#menu_requested?' do
    subject(:frontend) { Ruby::Nes::Frontends::Raylib.new(hidden: true) }

    after { frontend.close }

    context 'when no key or button is pressed' do
      it 'is false' do
        expect(frontend).not_to be_menu_requested
      end
    end
  end

  describe '#resume' do
    subject(:frontend) { Ruby::Nes::Frontends::Raylib.new(hidden: true) }

    let(:x_key) { Ruby::Nes::Frontends::Raylib::KEY_CODES.fetch('x') }

    after { frontend.close }

    context 'when L + R on the gamepad closed the menu' do
      before do
        allow(Ruby::Nes::Frontends::RaylibInput).to receive_messages(
          key_down?: false, gamepad_available?: true, gamepad_button_down?: true, left_stick: [0.0, 0.0]
        )
        frontend.present(Array.new(Ruby::Nes::Ppu::Picture::WIDTH * Ruby::Nes::Ppu::Picture::HEIGHT, 0x0F))
      end

      it 'asks for the menu no more' do
        frontend.resume

        expect(frontend).not_to be_menu_requested
      end
    end

    context 'when a button is held as the menu closes' do
      before do
        allow(Ruby::Nes::Frontends::RaylibInput).to receive_messages(gamepad_available?: false)
        allow(Ruby::Nes::Frontends::RaylibInput).to receive(:key_down?) { |code| code == x_key }
      end

      it 'keeps it from the controllers until let go', :aggregate_failures do
        frontend.resume

        expect(frontend.button_states).to eq([0, 0])
        allow(Ruby::Nes::Frontends::RaylibInput).to receive(:key_down?).and_return(false)
        frontend.button_states
        allow(Ruby::Nes::Frontends::RaylibInput).to receive(:key_down?) { |code| code == x_key }
        expect(frontend.button_states).to eq([Ruby::Nes::Input::Controller::BUTTONS.fetch(:a), 0])
      end
    end
  end

  describe '#next_screen' do
    subject(:frontend) { Ruby::Nes::Frontends::Raylib.new(hidden: true) }

    let(:x_key) { Ruby::Nes::Frontends::Raylib::KEY_CODES.fetch('x') }

    after { frontend.close }

    context 'when audio is queued' do
      it 'takes the order to start over' do
        frontend.queue_audio(Array.new(Ruby::Nes::Frontends::Raylib::SAMPLES_PER_FRAME * 3, 1000))

        expect { frontend.next_screen }.not_to raise_error
      end
    end

    context 'when L + R on the gamepad are held as the screen changes' do
      before do
        allow(Ruby::Nes::Frontends::RaylibInput).to receive_messages(
          key_down?: false, gamepad_available?: true, gamepad_button_down?: true, left_stick: [0.0, 0.0]
        )
        frontend.present(Array.new(Ruby::Nes::Ppu::Picture::WIDTH * Ruby::Nes::Ppu::Picture::HEIGHT, 0x0F))
      end

      it 'asks for the menu no more' do
        frontend.next_screen

        expect(frontend).not_to be_menu_requested
      end
    end

    # The A that chose BACK TO LIST would start the game again in the list (plan 38, review).
    context 'when a button is held as the screen changes' do
      before do
        allow(Ruby::Nes::Frontends::RaylibInput).to receive_messages(gamepad_available?: false)
        allow(Ruby::Nes::Frontends::RaylibInput).to receive(:key_down?) { |code| code == x_key }
      end

      it 'keeps it from the controllers until let go', :aggregate_failures do
        frontend.next_screen

        expect(frontend.button_states).to eq([0, 0])
        allow(Ruby::Nes::Frontends::RaylibInput).to receive(:key_down?).and_return(false)
        frontend.button_states
        allow(Ruby::Nes::Frontends::RaylibInput).to receive(:key_down?) { |code| code == x_key }
        expect(frontend.button_states).to eq([Ruby::Nes::Input::Controller::BUTTONS.fetch(:a), 0])
      end
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
