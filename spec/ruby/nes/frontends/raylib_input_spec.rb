# frozen_string_literal: true

# A smoke test of the controllers' input on raylib (plan 36): the keyboard and the gamepads as Frontends::Players and
# Frontends::Gamepad read them, asked once a hidden window is open (RaylibCanvas). raylib reads up to four gamepads,
# numbered 0 to 3; the machine running the specs may have a pad plugged in as gamepad 0, so the absent pad here is the
# last one. Skipped when the optional `frontends` group is not installed.
RSpec.describe 'Ruby::Nes::Frontends::RaylibInput', frontend_library: 'ruby/nes/frontends/raylib' do
  describe '.key_down?' do
    subject(:input) { Ruby::Nes::Frontends::RaylibInput }

    before { RaylibCanvas.open }

    after { RaylibCanvas.close }

    context 'when the key is not held' do
      it 'is false' do
        expect(input).not_to be_key_down(Raylib::KEY_X)
      end
    end
  end

  describe '.gamepad_available?' do
    subject(:input) { Ruby::Nes::Frontends::RaylibInput }

    before { RaylibCanvas.open }

    after { RaylibCanvas.close }

    context 'when no gamepad is plugged in with that number' do
      let(:absent_gamepad) { 3 }

      it 'is false' do
        expect(input).not_to be_gamepad_available(absent_gamepad)
      end
    end
  end

  describe '.gamepad_button_down?' do
    subject(:input) { Ruby::Nes::Frontends::RaylibInput }

    before { RaylibCanvas.open }

    after { RaylibCanvas.close }

    context 'when no gamepad is plugged in with that number' do
      let(:absent_gamepad) { 3 }

      it 'is false' do
        expect(input).not_to be_gamepad_button_down(absent_gamepad, Raylib::GAMEPAD_BUTTON_MIDDLE_RIGHT)
      end
    end
  end

  describe '.left_stick' do
    subject(:input) { Ruby::Nes::Frontends::RaylibInput }

    before { RaylibCanvas.open }

    after { RaylibCanvas.close }

    context 'when no gamepad is plugged in with that number' do
      let(:absent_gamepad) { 3 }

      it 'rests at the centre' do
        expect(input.left_stick(absent_gamepad)).to eq([0.0, 0.0])
      end
    end
  end
end
