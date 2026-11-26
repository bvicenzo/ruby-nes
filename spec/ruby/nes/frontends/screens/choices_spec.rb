# frozen_string_literal: true

require 'ruby/nes/frontends/screens'

# The entries of a menu, one under the other (plan 38): the pause menu's, the list's menu's, the slot picker's. Told
# each frame the buttons pressed on controller 1 (Screens::ButtonPresses), up and down move the focus an entry, stopping
# at the ends (Screens::Cursor); then A or Start choose the entry in focus, unless it is unavailable (greyed: LOAD STATE
# with no state). B goes back, before anything else pressed with it. Masks are in report order
# (Input::Controller::BUTTONS: bit 0 A, 1 B, 3 Start, 4 Up, 5 Down).
RSpec.describe Ruby::Nes::Frontends::Screens::Choices do
  describe '#tick' do
    context 'when B is pressed' do
      context 'and A is pressed with it' do
        subject(:choices) { described_class.new(entries: %i[resume reset quit]) }

        it 'goes back' do
          expect(choices.tick(0b0000_0011)).to eq(described_class::BACK)
        end
      end

      context 'and nothing else is pressed' do
        subject(:choices) { described_class.new(entries: %i[resume reset quit]) }

        it 'goes back' do
          expect(choices.tick(0b0000_0010)).to eq(described_class::BACK)
        end
      end
    end

    context 'when B is not pressed' do
      context 'and nothing is pressed' do
        subject(:choices) { described_class.new(entries: %i[resume reset quit], focus: 1) }

        it 'chooses nothing, the focus where it was', :aggregate_failures do
          expect(choices.tick(0)).to be_nil
          expect(choices.focus).to eq(1)
        end
      end

      context 'and up is pressed' do
        subject(:choices) { described_class.new(entries: %i[resume reset quit], focus: 1) }

        it 'chooses nothing, the focus on the entry above', :aggregate_failures do
          expect(choices.tick(0b0001_0000)).to be_nil
          expect(choices.focus).to eq(0)
        end
      end

      context 'and down is pressed' do
        subject(:choices) { described_class.new(entries: %i[resume reset quit], focus: 1) }

        it 'chooses nothing, the focus on the entry below', :aggregate_failures do
          expect(choices.tick(0b0010_0000)).to be_nil
          expect(choices.focus).to eq(2)
        end
      end

      context 'and Start is pressed' do
        subject(:choices) { described_class.new(entries: %i[resume reset quit], focus: 1) }

        it 'chooses the entry in focus' do
          expect(choices.tick(0b0000_1000)).to eq(:reset)
        end
      end

      context 'and A is pressed' do
        context 'but the entry in focus is unavailable' do
          subject(:choices) do
            described_class.new(entries: %i[resume load_state quit], unavailable: [:load_state], focus: 1)
          end

          it 'chooses nothing' do
            expect(choices.tick(0b0000_0001)).to be_nil
          end
        end

        context 'and down is pressed with it' do
          subject(:choices) { described_class.new(entries: %i[resume reset quit], focus: 1) }

          it 'chooses the entry below' do
            expect(choices.tick(0b0010_0001)).to eq(:quit)
          end
        end

        context 'and the entry in focus is available' do
          subject(:choices) do
            described_class.new(entries: %i[resume load_state quit], unavailable: [:load_state], focus: 2)
          end

          it 'chooses it' do
            expect(choices.tick(0b0000_0001)).to eq(:quit)
          end
        end
      end
    end
  end

  describe '#available?' do
    subject(:choices) { described_class.new(entries: %i[resume load_state], unavailable: [:load_state]) }

    context 'when the entry is unavailable' do
      it 'is false' do
        expect(choices).not_to be_available(:load_state)
      end
    end

    context 'when the entry is not unavailable' do
      it 'is true' do
        expect(choices).to be_available(:resume)
      end
    end
  end
end
