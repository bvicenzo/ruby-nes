# frozen_string_literal: true

require_relative '../../bench/frontend_benchmark'

# The arguments of bench/frontends.rb (plan 17, decision 2): one ROM, the backend to run it in, and how: a number of
# frames, at least 2 so that one frame time is measured (otherwise until the window closes), the test tone, a hidden
# window (for specs).
RSpec.describe FrontendBenchmark::Options do
  describe '.parse' do
    context 'when an option is invalid' do
      context 'and it names an unknown backend' do
        let(:arguments) { %w[game.nes --backend gosu] }

        it 'raises InvalidArgument' do
          expect { described_class.parse(arguments) }.to raise_error(OptionParser::InvalidArgument, /gosu/)
        end
      end

      context 'and it asks for fewer than 2 frames' do
        let(:arguments) { %w[game.nes --backend raylib --frames 1] }

        it 'raises InvalidArgument' do
          expect { described_class.parse(arguments) }.to raise_error(OptionParser::InvalidArgument, /at least 2/)
        end
      end
    end

    context 'when the options are valid' do
      context 'but no ROM is given' do
        let(:arguments) { %w[--backend raylib] }

        it 'raises MissingArgument' do
          expect { described_class.parse(arguments) }.to raise_error(OptionParser::MissingArgument, /ROM/)
        end
      end

      context 'but several ROMs are given' do
        let(:arguments) { %w[first.nes second.nes --backend raylib] }

        it 'raises NeedlessArgument' do
          expect { described_class.parse(arguments) }.to raise_error(OptionParser::NeedlessArgument, /second.nes/)
        end
      end

      context 'and one ROM is given' do
        context 'but no backend' do
          let(:arguments) { %w[game.nes] }

          it 'raises MissingArgument naming --backend' do
            expect { described_class.parse(arguments) }.to raise_error(OptionParser::MissingArgument, /--backend/)
          end
        end

        context 'and a backend' do
          context 'and nothing else' do
            let(:arguments) { %w[game.nes --backend raylib] }

            it 'runs until the window closes, silent and visible' do
              expect(described_class.parse(arguments)).to have_attributes(
                rom_path: 'game.nes',
                backend: 'raylib',
                frames: nil,
                tone_amplitude: 0,
                hidden: false
              )
            end
          end

          context 'and a frame count' do
            let(:arguments) { %w[game.nes --backend raylib --frames 600] }

            it 'runs that many frames' do
              expect(described_class.parse(arguments).frames).to eq(600)
            end
          end

          context 'and --tone' do
            let(:arguments) { %w[game.nes --backend raylib --tone] }

            it 'plays the tone' do
              expect(described_class.parse(arguments).tone_amplitude).to eq(8_000)
            end
          end

          context 'and --hidden' do
            let(:arguments) { %w[game.nes --backend raylib --hidden] }

            it 'hides the window' do
              expect(described_class.parse(arguments).hidden).to be(true)
            end
          end
        end
      end
    end
  end
end
