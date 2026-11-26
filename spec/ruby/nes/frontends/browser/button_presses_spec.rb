# frozen_string_literal: true

require 'ruby/nes/frontends/browser'

# The buttons the ROM browser takes as pressed in a frame (plan 37, decision 6), from the mask of controller 1's
# buttons held in it (Input::Controller::BUTTONS): a button is pressed on the frame it starts being held. A direction
# held on is pressed again on its 21st frame held (after a delay of 20 frames) and every 6 frames from then on, as a
# list scrolls; A, B, Select and Start never repeat, so a button held as a game ends starts nothing. Each button is
# timed on its own; releasing it starts the delay over.
RSpec.describe Ruby::Nes::Frontends::Browser::ButtonPresses do
  describe '#presses' do
    subject(:button_presses) { described_class.new }

    let(:up) { Ruby::Nes::Input::Controller::BUTTONS.fetch(:up) }
    let(:down) { Ruby::Nes::Input::Controller::BUTTONS.fetch(:down) }

    context 'when a button was not held the frame before' do
      it 'presses it' do
        expect(button_presses.presses(up)).to eq(up)
      end
    end

    context 'when a direction stays held' do
      context 'and for fewer frames than the delay' do
        before { button_presses.presses(up) }

        it 'does not press it again' do
          expect(Array.new(19) { button_presses.presses(up) }).to all(eq(0))
        end
      end

      context 'and for the delay' do
        before { 20.times { button_presses.presses(up) } }

        it 'presses it again on the next frame' do
          expect(button_presses.presses(up)).to eq(up)
        end
      end

      context 'and past the delay' do
        before { 21.times { button_presses.presses(up) } }

        it 'presses it again every 6 frames' do
          expect(Array.new(12) { button_presses.presses(up) }).to eq([0, 0, 0, 0, 0, up, 0, 0, 0, 0, 0, up])
        end
      end
    end

    context 'when a button that is not a direction stays held' do
      let(:start) { Ruby::Nes::Input::Controller::BUTTONS.fetch(:start) }

      before { button_presses.presses(start) }

      it 'never presses it again' do
        expect(Array.new(40) { button_presses.presses(start) }).to all(eq(0))
      end
    end

    context 'when a button is released and held again' do
      before do
        10.times { button_presses.presses(up) }
        button_presses.presses(0)
      end

      it 'presses it at once and starts the delay over' do
        expect(Array.new(21) { button_presses.presses(up) }).to eq([up, *Array.new(19, 0), up])
      end
    end

    context 'when two buttons are held from different frames' do
      before do
        10.times { button_presses.presses(up) }
      end

      it 'times each on its own' do
        both = Ruby::Nes::Bits.set_flag(up, down)

        expect(Array.new(11) { button_presses.presses(both) }).to eq([down, *Array.new(9, 0), up])
      end
    end
  end
end
