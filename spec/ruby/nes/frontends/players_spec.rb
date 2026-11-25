# frozen_string_literal: true

require 'ruby/nes/frontends/players'
require 'ruby/nes/frontends/raylib_input'

# The window's inputs as the console's two controllers (plan 36, decision 2): port 1 is the keyboard and the first
# gamepad (raylib's gamepad 0), their buttons combined; port 2 is the second gamepad (gamepad 1). A gamepad is read
# only while the library says it is available, asked every frame, so pulling one out releases its buttons (decision
# 6). Each port's opposite directions cancel once combined (Frontends::OppositeDirections). Key codes here are
# arbitrary integers, and masks are in report order (Input::Controller::BUTTONS: bit 0 A, 1 B, 3 Start, 4 Up, 5 Down,
# 6 Left, 7 Right).
RSpec.describe Ruby::Nes::Frontends::Players do
  describe '#button_states' do
    subject(:players) { described_class.new(keyboard:, gamepad:) }

    let(:keyboard) { Ruby::Nes::Frontends::Controls.new({ 88 => :a, 263 => :left }) }
    let(:gamepad) { instance_double(Ruby::Nes::Frontends::Gamepad) }
    let(:input) { class_double(Ruby::Nes::Frontends::RaylibInput) }

    context 'when no gamepad is available' do
      before do
        allow(input).to receive(:key_down?) { |code| code == 88 }
        allow(input).to receive(:gamepad_available?).and_return(false)
        allow(gamepad).to receive(:buttons)
      end

      it 'holds the keyboard on port 1 and nothing on port 2, asking no gamepad', :aggregate_failures do
        expect(players.button_states(input)).to eq([0b0000_0001, 0])
        expect(gamepad).not_to have_received(:buttons)
      end
    end

    context 'when only gamepad 0 is available' do
      let(:a_and_start) { 0b0000_1001 }

      before do
        allow(input).to receive(:key_down?) { |code| code == 88 }
        allow(input).to receive(:gamepad_available?, &:zero?)
        allow(gamepad).to receive(:buttons).with(0, input).and_return(0b0000_1000)
      end

      it 'holds the keyboard and gamepad 0 on port 1 and nothing on port 2' do
        expect(players.button_states(input)).to eq([a_and_start, 0])
      end
    end

    context 'when only gamepad 1 is available' do
      before do
        allow(input).to receive(:key_down?) { |code| code == 88 }
        allow(input).to receive(:gamepad_available?) { |gamepad| gamepad == 1 }
        allow(gamepad).to receive(:buttons).with(1, input).and_return(0b0000_0010)
      end

      it 'holds the keyboard on port 1 and gamepad 1 on port 2' do
        expect(players.button_states(input)).to eq([0b0000_0001, 0b0000_0010])
      end
    end

    context 'when gamepads 0 and 1 are available' do
      context 'and the keyboard and gamepad 0 hold opposite directions' do
        before do
          allow(input).to receive(:key_down?) { |code| code == 263 }
          allow(input).to receive(:gamepad_available?).and_return(true)
          allow(gamepad).to receive(:buttons).with(0, input).and_return(0b1000_0000)
          allow(gamepad).to receive(:buttons).with(1, input).and_return(0)
        end

        it 'releases both on port 1' do
          expect(players.button_states(input)).to eq([0, 0])
        end
      end

      context 'and gamepad 1 holds opposite directions' do
        let(:up_and_down) { 0b0011_0000 }

        before do
          allow(input).to receive_messages(key_down?: false, gamepad_available?: true)
          allow(gamepad).to receive(:buttons).with(0, input).and_return(0)
          allow(gamepad).to receive(:buttons).with(1, input).and_return(up_and_down)
        end

        it 'releases both on port 2' do
          expect(players.button_states(input)).to eq([0, 0])
        end
      end

      context 'and no port holds opposite directions' do
        let(:a_and_left_and_start) { 0b0100_1001 }

        before do
          allow(input).to receive_messages(key_down?: true, gamepad_available?: true)
          allow(gamepad).to receive(:buttons).with(0, input).and_return(0b0000_1000)
          allow(gamepad).to receive(:buttons).with(1, input).and_return(0b0000_0010)
        end

        it 'holds the keyboard and gamepad 0 on port 1 and gamepad 1 on port 2' do
          expect(players.button_states(input)).to eq([a_and_left_and_start, 0b0000_0010])
        end
      end
    end
  end
end
