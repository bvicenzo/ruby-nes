# frozen_string_literal: true

require 'ruby/nes/frontends/held_over'

# The controllers' buttons held as a menu closes (plan 38, scope 3): told the buttons held then, it takes them out of
# what both controllers hold from then on, each until it is let go, so the A that chose RESUME does not make Mario
# jump, nor a held Start pause the game. A button let go and held again counts. Masks are in report order
# (Input::Controller::BUTTONS: bit 0 A, 1 B, 3 Start, 7 Right), `[first, second]`.
RSpec.describe Ruby::Nes::Frontends::HeldOver do
  describe '#filter' do
    subject(:held_over) { described_class.new }

    context 'when nothing is held over' do
      it 'gives the buttons held' do
        expect(held_over.filter([0b0000_1001, 0b1000_0000])).to eq([0b0000_1001, 0b1000_0000])
      end
    end

    context 'when buttons are held over' do
      let(:a_and_start) { 0b0000_1001 }
      let(:right) { 0b1000_0000 }

      before { held_over.hold([a_and_start, right]) }

      context 'and a button not held over is held' do
        it 'gives it' do
          expect(held_over.filter([0b0000_0010, 0b0000_0001])).to eq([0b0000_0010, 0b0000_0001])
        end
      end

      context 'and the held over buttons are still held' do
        it 'leaves them out' do
          expect(held_over.filter([a_and_start, right])).to eq([0, 0])
        end
      end

      context 'and a held over button was let go at an earlier filter' do
        before { held_over.filter([0b0000_1000, 0]) }

        it 'gives it once it is held again, the others still left out' do
          expect(held_over.filter([a_and_start, right])).to eq([0b0000_0001, right])
        end
      end
    end
  end
end
