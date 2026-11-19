# frozen_string_literal: true

require 'ruby/nes/command_line'

# The command line's arguments (plan 16, decision 7): `ruby-nes ROM --headless --frames N [--screenshot FRAME:PATH]
# [--input SCRIPT]`. Frames count from 1, in decimal; 60 frames, one second of emulation, when --frames is not given.
# --help and --version ask only for information, so they need no ROM.
RSpec.describe Ruby::Nes::CommandLine::Options do
  describe '.parse' do
    context 'when --help is given' do
      let(:arguments) { %w[--help] }

      it 'asks to print the usage and the options' do
        expect(described_class.parse(arguments).information).to include('Usage: ruby-nes ROM', '--screenshot')
      end
    end

    context 'when --version is given' do
      let(:arguments) { %w[--version] }

      it 'asks to print the version' do
        expect(described_class.parse(arguments).information).to eq("ruby-nes #{Ruby::Nes::VERSION}")
      end
    end

    context 'when neither --help nor --version is given' do
      context 'and no ROM is given' do
        let(:arguments) { %w[--headless] }

        it 'raises a parse error naming the ROM' do
          expect { described_class.parse(arguments) }.to raise_error(OptionParser::ParseError, /ROM/)
        end
      end

      context 'and a ROM is given' do
        context 'but more than one' do
          let(:arguments) { %w[game.nes other.nes] }

          it 'raises a parse error naming the extra one' do
            expect { described_class.parse(arguments) }.to raise_error(OptionParser::ParseError, /other\.nes/)
          end
        end

        context 'and only one' do
          context 'but --frames is below 1' do
            let(:arguments) { %w[game.nes --frames 0] }

            it 'raises a parse error' do
              expect { described_class.parse(arguments) }.to raise_error(OptionParser::ParseError, /--frames 0/)
            end
          end

          context 'but a --screenshot is not FRAME:PATH' do
            let(:arguments) { %w[game.nes --screenshot out.png] }

            it 'raises a parse error' do
              expect { described_class.parse(arguments) }.to raise_error(OptionParser::ParseError, /out\.png/)
            end
          end

          context 'but a --screenshot frame is below 1' do
            let(:arguments) { %w[game.nes --screenshot 0:out.png] }

            it 'raises a parse error' do
              expect { described_class.parse(arguments) }.to raise_error(OptionParser::ParseError, /at least 1/)
            end
          end

          context 'but a --screenshot frame is past the last frame run' do
            let(:arguments) { %w[game.nes --frames 4 --screenshot 5:out.png] }

            it 'raises a parse error' do
              expect { described_class.parse(arguments) }.to raise_error(OptionParser::ParseError, /frame 5.*4 frames/)
            end
          end

          context 'but two --screenshot options name the same frame' do
            let(:arguments) { %w[game.nes --screenshot 2:a.png --screenshot 2:b.png] }

            it 'raises a parse error' do
              expect { described_class.parse(arguments) }.to raise_error(OptionParser::ParseError, /frame 2/)
            end
          end

          context 'and every option is valid' do
            context 'and no option is given' do
              let(:arguments) { %w[game.nes] }

              it 'runs 60 frames in a window, with no screenshot, no input script and no information asked' do
                expect(described_class.parse(arguments)).to have_attributes(
                  rom_path: 'game.nes', headless: false, frames: 60, screenshots: {}, input_path: nil, information: nil
                )
              end
            end

            context 'and every option is given' do
              let(:arguments) do
                %w[--headless game.nes --frames 120 --screenshot 60:a.png --screenshot 120:b:c.png --input moves.yml]
              end

              it 'holds each of them' do
                expect(described_class.parse(arguments)).to have_attributes(
                  rom_path: 'game.nes',
                  headless: true,
                  frames: 120,
                  screenshots: { 60 => 'a.png', 120 => 'b:c.png' },
                  input_path: 'moves.yml'
                )
              end
            end

            context 'and the numbers have leading zeros' do
              let(:arguments) { %w[game.nes --frames 010 --screenshot 08:a.png] }

              it 'reads them as decimal' do
                expect(described_class.parse(arguments)).to have_attributes(frames: 10, screenshots: { 8 => 'a.png' })
              end
            end
          end
        end
      end
    end
  end
end
