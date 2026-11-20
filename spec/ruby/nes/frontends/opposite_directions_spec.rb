# frozen_string_literal: true

require 'ruby/nes/frontends/opposite_directions'

# A keyboard lets Left and Right, or Up and Down, be held together, which a controller's D-pad does not; NESdev
# documents nothing to emulate (https://www.nesdev.org/wiki/Standard_controller), so the windowed frontend cancels
# them (plan 18, decision 3): a pair held together reaches the controller as neither. Masks are in report order
# (Input::Controller::BUTTONS).
RSpec.describe Ruby::Nes::Frontends::OppositeDirections do
  describe '.filter' do
    context 'when no direction is held' do
      let(:a_and_start) { 0b0000_1001 }

      it 'leaves the buttons as they are' do
        expect(described_class.filter(a_and_start)).to eq(a_and_start)
      end
    end

    context 'when directions are held' do
      context 'but none opposite another' do
        let(:a_up_and_right) { 0b1001_0001 }

        it 'leaves the buttons as they are' do
          expect(described_class.filter(a_up_and_right)).to eq(a_up_and_right)
        end
      end

      context 'and left and right are held together' do
        let(:a_up_left_and_right) { 0b1101_0001 }

        it 'releases left and right only' do
          expect(described_class.filter(a_up_left_and_right)).to eq(0b0001_0001)
        end
      end

      context 'and up and down are held together' do
        let(:b_up_down_and_left) { 0b0111_0010 }

        it 'releases up and down only' do
          expect(described_class.filter(b_up_down_and_left)).to eq(0b0100_0010)
        end
      end

      context 'and all four are held' do
        let(:select_and_every_direction) { 0b1111_0100 }

        it 'releases every direction only' do
          expect(described_class.filter(select_and_every_direction)).to eq(0b0000_0100)
        end
      end
    end
  end
end
