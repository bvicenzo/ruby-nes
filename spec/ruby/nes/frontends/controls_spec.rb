# frozen_string_literal: true

require 'ruby/nes/frontends/controls'

# Inputs bound to the buttons of a standard controller, a keyboard's keys (plan 17) or a gamepad's buttons (plan 36): a
# windowed frontend asks it for the controller's mask once per frame, telling it which of its library's input codes are
# held. Codes here are arbitrary integers, as each graphics library numbers its keys and buttons its own way.
RSpec.describe Ruby::Nes::Frontends::Controls do
  describe '.new' do
    context 'when a binding names something that is not a controller button' do
      let(:bindings) { { 90 => :b, 81 => :turbo, 87 => :rewind } }

      it 'raises ArgumentError naming it' do
        expect { described_class.new(bindings) }.to raise_error(ArgumentError, /turbo, rewind/)
      end
    end

    context 'when every binding names a controller button' do
      let(:bindings) { { 90 => :b, 88 => :a } }

      it 'builds the controls' do
        expect { described_class.new(bindings) }.not_to raise_error
      end
    end
  end

  describe '#buttons' do
    subject(:controls) { described_class.new(bindings) }

    context 'when no input is bound' do
      let(:bindings) { {} }

      it 'holds no button' do
        expect(controls.buttons { true }).to eq(0)
      end
    end

    context 'when inputs are bound' do
      context 'but none of them is held' do
        let(:bindings) { { 90 => :b, 88 => :a } }

        it 'holds no button' do
          expect(controls.buttons { false }).to eq(0)
        end
      end

      context 'and only an input that is not bound is held' do
        let(:bindings) { { 90 => :b, 88 => :a } }
        let(:unbound_input) { 32 }

        it 'holds no button' do
          expect(controls.buttons { |code| code == unbound_input }).to eq(0)
        end
      end

      context 'and one bound input is held' do
        let(:bindings) { { 90 => :b, 88 => :a } }

        it "holds that input's button only" do
          expect(controls.buttons { |code| code == 90 }).to eq(Ruby::Nes::Input::Controller::BUTTONS[:b])
        end
      end

      context 'and inputs bound to different buttons are held' do
        let(:bindings) { { 90 => :b, 88 => :a, 257 => :start } }
        let(:held_inputs) { [90, 257] }

        it 'holds every one of their buttons' do
          b_and_start = Ruby::Nes::Bits.set_flag(
            Ruby::Nes::Input::Controller::BUTTONS[:b],
            Ruby::Nes::Input::Controller::BUTTONS[:start]
          )

          expect(controls.buttons { |code| held_inputs.include?(code) }).to eq(b_and_start)
        end
      end

      context 'and inputs bound to opposite directions are held' do
        let(:bindings) { { 262 => :right, 263 => :left } }

        it 'holds both directions' do
          left_and_right = Ruby::Nes::Bits.set_flag(
            Ruby::Nes::Input::Controller::BUTTONS[:left],
            Ruby::Nes::Input::Controller::BUTTONS[:right]
          )

          expect(controls.buttons { true }).to eq(left_and_right)
        end
      end

      context 'and two inputs are bound to the same button' do
        context 'and one of them is held' do
          let(:bindings) { { 257 => :start, 32 => :start } }

          it 'holds that button' do
            expect(controls.buttons { |code| code == 32 }).to eq(Ruby::Nes::Input::Controller::BUTTONS[:start])
          end
        end

        context 'and both are held' do
          let(:bindings) { { 257 => :start, 32 => :start } }

          it 'holds that button only' do
            expect(controls.buttons { true }).to eq(Ruby::Nes::Input::Controller::BUTTONS[:start])
          end
        end
      end
    end
  end
end
