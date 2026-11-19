# frozen_string_literal: true

# The standard controller (https://www.nesdev.org/wiki/Standard_controller,
# https://www.nesdev.org/wiki/Controller_reading). Bit 0 of a $4016 write is the strobe: "Writing 1 to $4016 causes the
# register to fill its parallel inputs from the buttons currently held", and while it stays high reads "will keep
# returning the current state of the first button (A)". "Once S goes low, this reloading will stop", so the buttons are
# latched as it falls; "Other bits are ignored". Each read then reports the next button, "A, B, Select, Start, Up, Down,
# Left, Right", "1 if pressed, 0 if not pressed", and "All subsequent reads will return 1 on official Nintendo brand
# controllers". A second write of 0 with the strobe already low reloads nothing (plan 15, decision 3).
RSpec.describe Ruby::Nes::Input::Controller do
  describe '#read' do
    subject(:controller) { described_class.new(buttons: held_buttons) }

    context 'when the strobe is high' do
      context 'and A is released' do
        let(:held_buttons) { 0xFE } # every button but A

        before { controller.strobe(0x01) }

        it 'returns 0' do
          expect(controller.read).to eq(0)
        end
      end

      context 'and A is pressed' do
        let(:held_buttons) { described_class::BUTTONS.fetch(:a) }

        before { controller.strobe(0x01) }

        it 'returns 1' do
          expect(controller.read).to eq(1)
        end
      end

      context 'and only B is pressed' do
        let(:held_buttons) { described_class::BUTTONS.fetch(:b) }

        context 'and it was read once already' do
          before do
            controller.strobe(0x01)
            controller.read
          end

          it 'returns 0' do
            expect(controller.read).to eq(0)
          end
        end
      end

      context 'and A was pressed after the strobe was written' do
        let(:held_buttons) { 0x00 }

        before { controller.strobe(0x01) }

        it 'returns 1' do
          controller.buttons = described_class::BUTTONS.fetch(:a)
          expect(controller.read).to eq(1)
        end
      end

      context 'and the written byte had every bit set' do
        let(:held_buttons) { described_class::BUTTONS.fetch(:a) }

        before { controller.strobe(0xFF) }

        it 'returns the state of A' do
          expect(controller.read).to eq(1)
        end
      end
    end

    context 'when the strobe fell after being high' do
      context 'and one button is held' do
        before do
          controller.strobe(0x01)
          controller.strobe(0x00)
        end

        context 'and it is A' do
          let(:held_buttons) { described_class::BUTTONS.fetch(:a) }

          it 'reports it on the first read' do
            expect(Array.new(8) { controller.read }).to eq([1, 0, 0, 0, 0, 0, 0, 0])
          end
        end

        context 'and it is B' do
          let(:held_buttons) { described_class::BUTTONS.fetch(:b) }

          it 'reports it on the second read' do
            expect(Array.new(8) { controller.read }).to eq([0, 1, 0, 0, 0, 0, 0, 0])
          end
        end

        context 'and it is Select' do
          let(:held_buttons) { described_class::BUTTONS.fetch(:select) }

          it 'reports it on the third read' do
            expect(Array.new(8) { controller.read }).to eq([0, 0, 1, 0, 0, 0, 0, 0])
          end
        end

        context 'and it is Start' do
          let(:held_buttons) { described_class::BUTTONS.fetch(:start) }

          it 'reports it on the fourth read' do
            expect(Array.new(8) { controller.read }).to eq([0, 0, 0, 1, 0, 0, 0, 0])
          end
        end

        context 'and it is Up' do
          let(:held_buttons) { described_class::BUTTONS.fetch(:up) }

          it 'reports it on the fifth read' do
            expect(Array.new(8) { controller.read }).to eq([0, 0, 0, 0, 1, 0, 0, 0])
          end
        end

        context 'and it is Down' do
          let(:held_buttons) { described_class::BUTTONS.fetch(:down) }

          it 'reports it on the sixth read' do
            expect(Array.new(8) { controller.read }).to eq([0, 0, 0, 0, 0, 1, 0, 0])
          end
        end

        context 'and it is Left' do
          let(:held_buttons) { described_class::BUTTONS.fetch(:left) }

          it 'reports it on the seventh read' do
            expect(Array.new(8) { controller.read }).to eq([0, 0, 0, 0, 0, 0, 1, 0])
          end
        end

        context 'and it is Right' do
          let(:held_buttons) { described_class::BUTTONS.fetch(:right) }

          it 'reports it on the eighth read' do
            expect(Array.new(8) { controller.read }).to eq([0, 0, 0, 0, 0, 0, 0, 1])
          end
        end
      end

      context 'and eight reads were made already' do
        let(:held_buttons) { 0x00 }

        before do
          controller.strobe(0x01)
          controller.strobe(0x00)
          8.times { controller.read }
        end

        it 'returns 1 on every further read' do
          expect(Array.new(3) { controller.read }).to eq([1, 1, 1])
        end
      end

      context 'and the buttons changed while the strobe was high' do
        let(:held_buttons) { described_class::BUTTONS.fetch(:a) }

        before { controller.strobe(0x01) }

        it 'reports the buttons held as it fell' do
          controller.buttons = described_class::BUTTONS.fetch(:right)
          controller.strobe(0x00)
          expect(Array.new(8) { controller.read }).to eq([0, 0, 0, 0, 0, 0, 0, 1])
        end
      end

      context 'and the buttons changed after it fell' do
        let(:held_buttons) { described_class::BUTTONS.fetch(:a) }

        before do
          controller.strobe(0x01)
          controller.strobe(0x00)
        end

        it 'keeps reporting the buttons held as it fell' do
          controller.buttons = described_class::BUTTONS.fetch(:right)
          expect(Array.new(8) { controller.read }).to eq([1, 0, 0, 0, 0, 0, 0, 0])
        end
      end

      context 'and 0 was written again in the middle of the sequence' do
        let(:held_buttons) { 0x05 } # A and Select

        before do
          controller.strobe(0x01)
          controller.strobe(0x00)
          controller.read
          controller.strobe(0x00)
        end

        it 'continues the sequence where it was' do
          expect(Array.new(7) { controller.read }).to eq([0, 1, 0, 0, 0, 0, 0])
        end
      end

      context 'and the falling byte had every other bit set' do
        let(:held_buttons) { 0x81 } # A and Right

        before do
          controller.strobe(0x01)
          controller.strobe(0xFE)
        end

        it 'reports the buttons in order' do
          expect(Array.new(8) { controller.read }).to eq([1, 0, 0, 0, 0, 0, 0, 1])
        end
      end
    end
  end
end
