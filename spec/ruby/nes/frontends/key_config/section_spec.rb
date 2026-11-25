# frozen_string_literal: true

require 'ruby/nes/frontends/key_config'

# One section of the window's config file (plan 18, decision 7): `keys:` names keyboard keys, `gamepad:` gamepad buttons
# (plan 36). Given what YAML loaded for it, it binds each action to a list of input names: the actions it names take
# its names, the others keep their defaults, except the ones the section gives to another action (the file wins). The
# section's actions are those of its defaults, here a small made-up set.
RSpec.describe Ruby::Nes::Frontends::KeyConfig::Section do
  describe '#bindings' do
    subject(:section) { described_class.new(name: 'keys', kind: 'key', defaults:) }

    let(:defaults) { { a: %w[x c], b: ['z'], start: ['enter'], pause: ['p'] } }

    context 'when the section is absent' do
      it 'keeps every default' do
        expect(section.bindings(nil)).to eq({ a: %w[x c], b: ['z'], start: ['enter'], pause: ['p'] })
      end
    end

    context 'when the section is given' do
      context 'but it is not a mapping' do
        it 'raises InvalidConfig naming the section and its kind of input' do
          expect { section.bindings(%w[x z]) }
            .to raise_error(Ruby::Nes::Frontends::KeyConfig::InvalidConfig, 'keys: maps actions to key names')
        end
      end

      context 'and it is a mapping' do
        context 'but it is empty' do
          it 'keeps every default' do
            expect(section.bindings({})).to eq({ a: %w[x c], b: ['z'], start: ['enter'], pause: ['p'] })
          end
        end

        context 'and it names actions' do
          context 'but some names are not actions' do
            let(:value) { { 'a' => 'x', 'turbo' => 't', 'rewind' => 'w' } }

            let(:message) { 'keys: not actions: turbo, rewind (it takes a, b, start, pause)' }

            it 'raises InvalidConfig naming the section, every one of them and the actions it takes' do
              expect { section.bindings(value) }.to raise_error(Ruby::Nes::Frontends::KeyConfig::InvalidConfig, message)
            end
          end

          context 'and every name is an action' do
            context 'but an action is given something other than a name or a list' do
              let(:value) { { 'a' => 'x', 'pause' => nil } }

              it 'raises InvalidConfig naming the section and the action' do
                expect { section.bindings(value) }
                  .to raise_error(Ruby::Nes::Frontends::KeyConfig::InvalidConfig, /\Akeys: pause takes/)
              end
            end

            context 'but an action is given a list holding something other than a name' do
              let(:value) { { 'b' => ['z', 3] } }

              it 'raises InvalidConfig naming the section and the action' do
                expect { section.bindings(value) }
                  .to raise_error(Ruby::Nes::Frontends::KeyConfig::InvalidConfig, /\Akeys: b takes/)
              end
            end

            context 'and every action is given names' do
              context 'and an action is given a name' do
                let(:value) { { 'pause' => 'space' } }

                it "replaces that action's default only" do
                  expect(section.bindings(value)).to eq({ a: %w[x c], b: ['z'], start: ['enter'], pause: ['space'] })
                end
              end

              context 'and an action is given a list of names' do
                let(:value) { { 'b' => %w[z left_control] } }

                it 'binds every name of the list' do
                  expect(section.bindings(value))
                    .to eq({ a: %w[x c], b: %w[z left_control], start: ['enter'], pause: ['p'] })
                end
              end

              context 'and an action is given the same name twice' do
                let(:value) { { 'b' => %w[z z] } }

                it 'binds it once' do
                  expect(section.bindings(value)).to eq({ a: %w[x c], b: ['z'], start: ['enter'], pause: ['p'] })
                end
              end

              context 'and an action is given an empty list' do
                let(:value) { { 'start' => [] } }

                it 'leaves the action without an input' do
                  expect(section.bindings(value)).to eq({ a: %w[x c], b: ['z'], start: [], pause: ['p'] })
                end
              end

              context 'and an action is given a name another action has by default' do
                let(:value) { { 'b' => 'c' } }

                it 'takes the name from that action' do
                  expect(section.bindings(value)).to eq({ a: ['x'], b: ['c'], start: ['enter'], pause: ['p'] })
                end
              end

              context 'and two actions are given the same name' do
                let(:value) { { 'a' => 'space', 'pause' => 'space' } }

                it 'binds it to both' do
                  expect(section.bindings(value)).to eq({ a: ['space'], b: ['z'], start: ['enter'], pause: ['space'] })
                end
              end
            end
          end
        end
      end
    end
  end
end
