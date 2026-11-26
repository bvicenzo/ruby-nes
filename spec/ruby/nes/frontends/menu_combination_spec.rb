# frozen_string_literal: true

require 'ruby/nes/frontends/menu_combination'
require 'ruby/nes/frontends/raylib_input'

# The pad's way into the menus (plan 38, decision 3): two gamepad buttons held together on the first gamepad (raylib's
# gamepad 0), L and R in the window. Polled once per frame, it is pressed on the poll where the second of the two
# becomes held, and not again until one of them is let go; an absent gamepad holds nothing. Started over as a menu
# closes or a screen changes, it is no longer pressed, the buttons still held being no new press. Button codes here are
# arbitrary integers, as raylib numbers its gamepad buttons its own way.
RSpec.describe Ruby::Nes::Frontends::MenuCombination do
  describe '#pressed?' do
    subject(:combination) { described_class.new(buttons: [left_shoulder, right_shoulder]) }

    let(:left_shoulder) { 9 }
    let(:right_shoulder) { 11 }
    let(:input) { class_double(Ruby::Nes::Frontends::RaylibInput) }

    context 'when the gamepad is absent' do
      before do
        allow(input).to receive(:gamepad_available?).with(0).and_return(false)
        allow(input).to receive(:gamepad_button_down?).and_return(true)
        combination.poll(input)
      end

      it 'is false' do
        expect(combination).not_to be_pressed
      end
    end

    context 'when the gamepad is present' do
      context 'but neither button is held' do
        before do
          allow(input).to receive(:gamepad_available?).with(0).and_return(true)
          allow(input).to receive(:gamepad_button_down?).and_return(false)
          combination.poll(input)
        end

        it 'is false' do
          expect(combination).not_to be_pressed
        end
      end

      context 'but only the first button is held' do
        before do
          allow(input).to receive(:gamepad_available?).with(0).and_return(true)
          allow(input).to receive(:gamepad_button_down?) { |gamepad, code| gamepad.zero? && code == left_shoulder }
          combination.poll(input)
        end

        it 'is false' do
          expect(combination).not_to be_pressed
        end
      end

      context 'but only the second button is held' do
        before do
          allow(input).to receive(:gamepad_available?).with(0).and_return(true)
          allow(input).to receive(:gamepad_button_down?) { |gamepad, code| gamepad.zero? && code == right_shoulder }
          combination.poll(input)
        end

        it 'is false' do
          expect(combination).not_to be_pressed
        end
      end

      context 'and both buttons are held' do
        context 'but both were held at the poll before' do
          before do
            allow(input).to receive(:gamepad_available?).with(0).and_return(true)
            allow(input).to receive(:gamepad_button_down?) { |gamepad, _code| gamepad.zero? }
            2.times { combination.poll(input) }
          end

          it 'is false' do
            expect(combination).not_to be_pressed
          end
        end

        context 'and there was no poll before' do
          before do
            allow(input).to receive(:gamepad_available?).with(0).and_return(true)
            allow(input).to receive(:gamepad_button_down?) { |gamepad, _code| gamepad.zero? }
            combination.poll(input)
          end

          it 'is true' do
            expect(combination).to be_pressed
          end
        end

        context 'and one of them was not held at the poll before' do
          before do
            allow(input).to receive(:gamepad_available?).with(0).and_return(true)
            allow(input).to receive(:gamepad_button_down?).with(0, left_shoulder).and_return(true)
            allow(input).to receive(:gamepad_button_down?).with(0, right_shoulder).and_return(false, true)
            2.times { combination.poll(input) }
          end

          it 'is true' do
            expect(combination).to be_pressed
          end
        end

        context 'and the gamepad was absent at the poll before' do
          before do
            allow(input).to receive(:gamepad_available?).with(0).and_return(false, true)
            allow(input).to receive(:gamepad_button_down?).and_return(true)
            2.times { combination.poll(input) }
          end

          it 'is true' do
            expect(combination).to be_pressed
          end
        end
      end
    end
  end

  describe '#restart' do
    subject(:combination) { described_class.new(buttons: [9, 11]) }

    let(:input) { class_double(Ruby::Nes::Frontends::RaylibInput) }

    before do
      allow(input).to receive(:gamepad_available?).with(0).and_return(true)
      allow(input).to receive(:gamepad_button_down?).and_return(true)
      combination.poll(input)
    end

    it 'is no longer pressed, the buttons still held being no new press at the next poll', :aggregate_failures do
      combination.restart

      expect(combination).not_to be_pressed
      combination.poll(input)
      expect(combination).not_to be_pressed
    end
  end
end
