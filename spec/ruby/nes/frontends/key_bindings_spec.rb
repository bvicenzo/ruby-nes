# frozen_string_literal: true

require 'ruby/nes/frontends/key_bindings'

# The inputs of a Frontends::KeyConfig section turned into the graphics library's codes (plan 18, decision 7): the
# keyboard's keys, or a gamepad's buttons (plan 36), named as `kind` in the errors. They are split between the
# controller's buttons (for Frontends::Controls) and the hotkeys (for Frontends::Hotkeys). An input drives one action
# only. The library's names and codes here are a small made-up table.
RSpec.describe Ruby::Nes::Frontends::KeyBindings do
  describe '.new' do
    let(:codes) { { 'x' => 88, 'z' => 90, 'p' => 80, 'escape' => 256 } }

    context 'when a name is not one of the library' do
      let(:keys) { { a: ['x'], b: ['zed'], quit: ['escape'] } }

      it 'raises InvalidConfig naming it, its action and the kind of input' do
        expect { described_class.new(keys, codes:, kind: 'gamepad button') }
          .to raise_error(Ruby::Nes::Frontends::KeyConfig::InvalidConfig, '"zed" (b) is not a gamepad button name')
      end
    end

    context 'when every name is one of the library' do
      context 'but an input is bound to two actions' do
        let(:keys) { { a: ['x'], b: ['z'], pause: ['z'] } }

        it 'raises InvalidConfig naming the input and both actions' do
          expect { described_class.new(keys, codes:, kind: 'key') }
            .to raise_error(Ruby::Nes::Frontends::KeyConfig::InvalidConfig, /"z".*b.*pause/)
        end
      end

      context 'and each input is bound to one action' do
        let(:keys) { { a: ['x'], b: ['z'], pause: ['p'] } }

        it 'builds the bindings' do
          expect { described_class.new(keys, codes:, kind: 'key') }.not_to raise_error
        end
      end
    end
  end

  describe '#controller' do
    subject(:key_bindings) { described_class.new(keys, codes:, kind: 'key') }

    let(:codes) { { 'x' => 88, 'z' => 90, 'space' => 32, 'p' => 80, 'escape' => 256 } }
    let(:keys) { { a: ['x'], b: %w[z space], start: [], pause: ['p'], quit: ['escape'] } }

    it 'binds the key codes of the buttons to their buttons' do
      expect(key_bindings.controller).to eq({ 88 => :a, 90 => :b, 32 => :b })
    end
  end

  describe '#hotkeys' do
    subject(:key_bindings) { described_class.new(keys, codes:, kind: 'key') }

    let(:codes) { { 'x' => 88, 'p' => 80, 'escape' => 256, 'q' => 81 } }
    let(:keys) { { a: ['x'], pause: ['p'], quit: %w[escape q], reset: [] } }

    it 'binds the key codes of the hotkeys to their actions' do
      expect(key_bindings.hotkeys).to eq({ 80 => :pause, 256 => :quit, 81 => :quit })
    end
  end
end
