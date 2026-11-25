# frozen_string_literal: true

require 'ruby/nes/frontends/key_config'

# The window's controls as the config file sets them (plan 18, decision 7; plan 36): a `keys:` section mapping each
# action, a controller button or a hotkey, to keyboard keys; a `gamepad:` section mapping controller buttons only to
# gamepad buttons (plan 36, decision 3); and `gamepad_mappings:`, text in the SDL GameControllerDB format for pads
# raylib does not know (plan 36, decision 4). Each section's rules are KeyConfig::Section's; anything else in the file
# is an error that names what is wrong.
RSpec.describe Ruby::Nes::Frontends::KeyConfig do
  describe '.parse' do
    context 'when the text cannot be loaded as YAML' do
      let(:text) { "keys:\n  a: [x\n" }

      it 'raises InvalidConfig' do
        expect { described_class.parse(text) }.to raise_error(described_class::InvalidConfig, /YAML/)
      end
    end

    context 'when the text is empty' do
      it 'keeps every default key and gamepad button, with no gamepad mappings', :aggregate_failures do
        key_config = described_class.parse('')

        expect(key_config.keys).to eq(described_class::DEFAULTS)
        expect(key_config.gamepad_buttons).to eq(described_class::GAMEPAD_DEFAULTS)
        expect(key_config.gamepad_mappings).to be_nil
      end
    end

    context 'when the text holds something other than a mapping' do
      let(:text) { "- a\n- x\n" }

      it 'raises InvalidConfig' do
        expect { described_class.parse(text) }.to raise_error(described_class::InvalidConfig, /keys, gamepad/)
      end
    end

    context 'when the text is a mapping' do
      context 'but it has a section it does not know' do
        let(:text) { "keys:\n  a: x\nvideo:\n  scale: 2\n" }

        it 'raises InvalidConfig naming it' do
          expect { described_class.parse(text) }.to raise_error(described_class::InvalidConfig, /video/)
        end
      end

      context 'and every section is known' do
        context 'but its gamepad section names a hotkey' do
          let(:text) { "gamepad:\n  a: right_face_right\n  pause: middle_right\n" }

          it 'raises InvalidConfig naming it' do
            expect { described_class.parse(text) }
              .to raise_error(described_class::InvalidConfig, /\Agamepad: not actions: pause \(it takes a, b, select,/)
          end
        end

        context 'but its gamepad mappings are not text' do
          let(:text) { "gamepad_mappings:\n  - 0300\n" }

          it 'raises InvalidConfig' do
            expect { described_class.parse(text) }.to raise_error(described_class::InvalidConfig, /gamepad_mappings:/)
          end
        end

        context 'and its sections are valid' do
          context 'and it has a keys section' do
            let(:text) { "keys:\n  pause: space\n" }

            it 'binds the keys it names, keeping the other defaults' do
              expect(described_class.parse(text).keys).to eq(described_class::DEFAULTS.merge(pause: ['space']))
            end
          end

          context 'and it has a gamepad section' do
            let(:text) { "gamepad:\n  a: right_trigger_1\n" }

            it 'binds the gamepad buttons it names, keeping the other defaults' do
              expect(described_class.parse(text).gamepad_buttons)
                .to eq(described_class::GAMEPAD_DEFAULTS.merge(a: ['right_trigger_1']))
            end
          end

          context 'and it has gamepad mappings' do
            let(:mappings) { "03000000790000001100000010010000,Pad,a:b2,b:b1,platform:Linux,\n" }
            let(:text) { "gamepad_mappings: #{mappings.inspect}\n" }

            it 'keeps their text' do
              expect(described_class.parse(text).gamepad_mappings).to eq(mappings)
            end
          end
        end
      end
    end
  end

  describe '#unbound_actions' do
    context 'when every action has a key' do
      subject(:key_config) { described_class.parse("keys:\n  pause: space\n") }

      it 'is empty' do
        expect(key_config.unbound_actions).to be_empty
      end
    end

    context 'when actions are left without a key' do
      subject(:key_config) { described_class.parse("keys:\n  a: z\n  reset: []\n") }

      it 'names them' do
        expect(key_config.unbound_actions).to contain_exactly(:b, :reset)
      end
    end

    context 'when actions are left without a gamepad button only' do
      subject(:key_config) { described_class.parse("gamepad:\n  start: []\n") }

      it 'is empty' do
        expect(key_config.unbound_actions).to be_empty
      end
    end
  end
end
