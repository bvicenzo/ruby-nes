# frozen_string_literal: true

require 'ruby/nes/frontends/stick_directions'

# A gamepad's analog stick as the D-pad (plan 36, decision 5): each axis, from -1.0 to 1.0 with left and up negative
# (raylib's GetGamepadAxisMovement), holds one of its two directions only past a dead zone of 0.5 (`.direction`); the
# horizontal axis is Left and Right, the vertical one Up and Down (`.buttons`). Masks are in report order
# (Input::Controller::BUTTONS: bit 4 Up, 5 Down, 6 Left, 7 Right).
RSpec.describe Ruby::Nes::Frontends::StickDirections do
  describe '.direction' do
    let(:left) { 0b0100_0000 }
    let(:right) { 0b1000_0000 }

    context 'when the axis is below -0.5' do
      it 'holds its negative direction' do
        expect(described_class.direction(-0.51, negative: :left, positive: :right)).to eq(left)
      end
    end

    context 'when the axis is at -0.5' do
      it 'holds nothing' do
        expect(described_class.direction(-0.5, negative: :left, positive: :right)).to eq(0)
      end
    end

    context 'when the axis is inside the dead zone' do
      it 'holds nothing' do
        expect(described_class.direction(0.3, negative: :left, positive: :right)).to eq(0)
      end
    end

    context 'when the axis is at 0.5' do
      it 'holds nothing' do
        expect(described_class.direction(0.5, negative: :left, positive: :right)).to eq(0)
      end
    end

    context 'when the axis is above 0.5' do
      it 'holds its positive direction' do
        expect(described_class.direction(0.51, negative: :left, positive: :right)).to eq(right)
      end
    end
  end

  describe '.buttons' do
    context 'when the stick is at rest' do
      it 'holds nothing' do
        expect(described_class.buttons(0.0, 0.0)).to eq(0)
      end
    end

    context 'when only the horizontal axis is past the dead zone' do
      let(:left) { 0b0100_0000 }

      it 'holds its direction' do
        expect(described_class.buttons(-1.0, 0.0)).to eq(left)
      end
    end

    context 'when only the vertical axis is past the dead zone' do
      let(:down) { 0b0010_0000 }

      it 'holds its direction' do
        expect(described_class.buttons(0.0, 1.0)).to eq(down)
      end
    end

    context 'when both axes are past the dead zone' do
      let(:up_and_right) { 0b1001_0000 }

      it 'holds both directions' do
        expect(described_class.buttons(1.0, -1.0)).to eq(up_and_right)
      end
    end
  end
end
