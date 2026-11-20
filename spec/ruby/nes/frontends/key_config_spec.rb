# frozen_string_literal: true

require 'ruby/nes/frontends/key_config'

# The keys of the windowed frontend as the config file sets them (plan 18, decision 7): a `keys:` section mapping each
# action, a controller button or a hotkey, to a key name or a list of key names. Actions it does not mention keep
# their default keys; anything else in the file is an error that names what is wrong.
RSpec.describe Ruby::Nes::Frontends::KeyConfig do
  describe '.parse' do
    let(:defaults) { described_class::DEFAULTS.transform_values { [it] } }

    context 'when the text cannot be loaded as YAML' do
      let(:text) { "keys:\n  a: [x\n" }

      it 'raises InvalidConfig' do
        expect { described_class.parse(text) }.to raise_error(described_class::InvalidConfig, /YAML/)
      end
    end

    context 'when the text is empty' do
      let(:text) { '' }

      it 'keeps every default key' do
        expect(described_class.parse(text).keys).to eq(defaults)
      end
    end

    context 'when the text holds something other than a mapping' do
      let(:text) { "- a\n- x\n" }

      it 'raises InvalidConfig' do
        expect { described_class.parse(text) }.to raise_error(described_class::InvalidConfig, /keys:/)
      end
    end

    context 'when the text is a mapping' do
      context 'but it has a section other than keys' do
        let(:text) { "keys:\n  a: x\nvideo:\n  scale: 2\n" }

        it 'raises InvalidConfig naming it' do
          expect { described_class.parse(text) }.to raise_error(described_class::InvalidConfig, /video/)
        end
      end

      context 'and its keys section is not a mapping' do
        let(:text) { "keys: [x, z]\n" }

        it 'raises InvalidConfig' do
          expect { described_class.parse(text) }.to raise_error(described_class::InvalidConfig, /keys:/)
        end
      end

      context 'and it has no keys section' do
        let(:text) { "--- {}\n" }

        it 'keeps every default key' do
          expect(described_class.parse(text).keys).to eq(defaults)
        end
      end

      context 'and its keys section is empty' do
        let(:text) { "keys:\n" }

        it 'keeps every default key' do
          expect(described_class.parse(text).keys).to eq(defaults)
        end
      end

      context 'and its keys section is a mapping' do
        context 'but it names something that is not an action' do
          let(:text) { "keys:\n  a: x\n  turbo: t\n  rewind: w\n" }

          it 'raises InvalidConfig naming it' do
            expect { described_class.parse(text) }.to raise_error(described_class::InvalidConfig, /turbo, rewind/)
          end
        end

        context 'and every name is an action' do
          context 'but an action is given something other than key names' do
            let(:text) { "keys:\n  a: x\n  quit: off\n" }

            it 'raises InvalidConfig naming it' do
              expect { described_class.parse(text) }.to raise_error(described_class::InvalidConfig, /quit/)
            end
          end

          context 'and every action is given key names' do
            context 'and an action is given a key' do
              let(:text) { "keys:\n  pause: space\n" }

              it "replaces that action's default key only" do
                expect(described_class.parse(text).keys).to eq(defaults.merge(pause: ['space']))
              end
            end

            context 'and an action is given a list of keys' do
              let(:text) { "keys:\n  b: [z, left_control]\n" }

              it 'binds every key of the list' do
                expect(described_class.parse(text).keys).to eq(defaults.merge(b: %w[z left_control]))
              end
            end

            context 'and an action is given the same key twice' do
              let(:text) { "keys:\n  b: [z, z]\n" }

              it 'binds it once' do
                expect(described_class.parse(text).keys).to eq(defaults.merge(b: ['z']))
              end
            end

            context 'and an action is given an empty list' do
              let(:text) { "keys:\n  reset: []\n" }

              it 'leaves the action without a key' do
                expect(described_class.parse(text).keys).to eq(defaults.merge(reset: []))
              end
            end

            context 'and an action is given a key another action has by default' do
              let(:text) { "keys:\n  a: z\n" }

              it 'takes the key from that action' do
                expect(described_class.parse(text).keys).to eq(defaults.merge(a: ['z'], b: []))
              end
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
  end
end
