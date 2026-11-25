# frozen_string_literal: true

require 'ruby/nes/frontends/gamepad'
require 'ruby/nes/frontends/raylib_input'

# The window's gamepads as standard controllers (plan 36): a pad's bound buttons (Frontends::Controls) and its left
# stick past the dead zone (Frontends::StickDirections) make one mask. Opposite directions stay, Frontends::Players
# cancels them per port. The input is the graphics library's, asked about that pad only; button codes here are
# arbitrary integers, and masks are in report order (Input::Controller::BUTTONS: bit 0 A, 1 B, 4 Up, 6 Left, 7 Right).
RSpec.describe Ruby::Nes::Frontends::Gamepad do
  describe '#buttons' do
    subject(:gamepad) { described_class.new(Ruby::Nes::Frontends::Controls.new(bindings)) }

    let(:bindings) { { 6 => :a, 7 => :b, 2 => :right } }
    let(:input) { class_double(Ruby::Nes::Frontends::RaylibInput) }

    context 'when no bound button is down and the stick is at rest' do
      before do
        allow(input).to receive(:gamepad_button_down?).with(1, anything).and_return(false)
        allow(input).to receive(:left_stick).with(1).and_return([0.0, 0.0])
      end

      it 'holds nothing' do
        expect(gamepad.buttons(1, input)).to eq(0)
      end
    end

    context 'when a bound button is down' do
      before do
        allow(input).to receive(:gamepad_button_down?) { |gamepad, code| gamepad == 1 && code == 6 }
        allow(input).to receive(:left_stick).with(1).and_return([0.0, 0.0])
      end

      it 'holds its button, asking about that pad only', :aggregate_failures do
        expect(gamepad.buttons(1, input)).to eq(0b0000_0001)
        expect(input).not_to have_received(:gamepad_button_down?).with(0, anything)
      end
    end

    context 'when the stick is past the dead zone' do
      before do
        allow(input).to receive(:gamepad_button_down?).with(1, anything).and_return(false)
        allow(input).to receive(:left_stick).with(1).and_return([0.0, -1.0])
      end

      it 'holds its direction' do
        expect(gamepad.buttons(1, input)).to eq(0b0001_0000)
      end
    end

    context 'when a button and the stick hold different buttons' do
      let(:b_and_up) { 0b0001_0010 }

      before do
        allow(input).to receive(:gamepad_button_down?) { |_gamepad, code| code == 7 }
        allow(input).to receive(:left_stick).with(1).and_return([0.0, -1.0])
      end

      it 'holds both' do
        expect(gamepad.buttons(1, input)).to eq(b_and_up)
      end
    end

    context 'when a button and the stick hold the same direction' do
      before do
        allow(input).to receive(:gamepad_button_down?) { |_gamepad, code| code == 2 }
        allow(input).to receive(:left_stick).with(1).and_return([1.0, 0.0])
      end

      it 'holds it' do
        expect(gamepad.buttons(1, input)).to eq(0b1000_0000)
      end
    end

    context 'when a button and the stick hold opposite directions' do
      let(:left_and_right) { 0b1100_0000 }

      before do
        allow(input).to receive(:gamepad_button_down?) { |_gamepad, code| code == 2 }
        allow(input).to receive(:left_stick).with(1).and_return([-1.0, 0.0])
      end

      it 'holds both' do
        expect(gamepad.buttons(1, input)).to eq(left_and_right)
      end
    end
  end
end
