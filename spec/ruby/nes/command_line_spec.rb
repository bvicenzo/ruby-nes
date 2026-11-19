# frozen_string_literal: true

require 'fileutils'
require 'stringio'
require 'tmpdir'
require 'ruby/nes/command_line'

# `ruby-nes ROM --headless --frames N [--screenshot FRAME:PATH] [--input SCRIPT]` (plan 16, decision 7): runs the ROM
# in the headless frontend and prints the frame count and the last frame's digest; the window arrives in plan 18. The
# exit status is 0 when the run completes, 1 with a message on the error output otherwise.
RSpec.describe Ruby::Nes::CommandLine do
  describe '#run' do
    let(:output) { StringIO.new }
    let(:error_output) { StringIO.new }

    context 'when the options are invalid' do
      subject(:command_line) { described_class.new(%w[--headless], output:, error_output:) }

      it 'prints the reason and the usage to the error output and fails', :aggregate_failures do
        expect(command_line.run).to eq(1)
        expect(error_output.string).to include('missing argument: ROM', 'Usage: ruby-nes ROM')
      end
    end

    context 'when the options are valid' do
      context 'but they only ask for information' do
        subject(:command_line) { described_class.new(%w[--version], output:, error_output:) }

        it 'prints it and succeeds', :aggregate_failures do
          expect(command_line.run).to eq(0)
          expect(output.string).to eq("ruby-nes #{Ruby::Nes::VERSION}\n")
        end
      end

      context 'but --headless is not given' do
        subject(:command_line) { described_class.new(%w[game.nes], output:, error_output:) }

        it 'prints that only the headless frontend exists and fails', :aggregate_failures do
          expect(command_line.run).to eq(1)
          expect(error_output.string).to include('--headless')
        end
      end

      context 'and --headless is given' do
        let(:directory) { Dir.mktmpdir }

        after { FileUtils.remove_entry(directory) }

        context 'but the ROM cannot be loaded' do
          subject(:command_line) do
            described_class.new(['--headless', File.join(directory, 'missing.nes')], output:, error_output:)
          end

          it 'prints the reason and fails', :aggregate_failures do
            expect(command_line.run).to eq(1)
            expect(error_output.string).to include('missing.nes')
          end
        end

        context 'and the ROM loads', test_rom: Nestest::ROM_PATH do
          let(:rom_path) { test_rom_path(Nestest::ROM_PATH) }
          let(:script_path) { File.join(directory, 'moves.yml') }
          let(:screenshot_path) { File.join(directory, 'second.png') }

          context 'and no input script is given' do
            subject(:command_line) do
              described_class.new(['--headless', rom_path, '--frames', '1'], output:, error_output:)
            end

            it 'runs the frames and prints the last digest', :aggregate_failures do
              expect(command_line.run).to eq(0)
              expect(output.string).to match(/\A1 frames, last frame SHA-256 \h{64}\n\z/)
            end
          end

          context 'but the input script cannot be read' do
            subject(:command_line) do
              described_class.new(['--headless', rom_path, '--input', script_path], output:, error_output:)
            end

            it 'prints the reason and fails', :aggregate_failures do
              expect(command_line.run).to eq(1)
              expect(error_output.string).to include('moves.yml')
            end
          end

          context 'but the input script is invalid' do
            subject(:command_line) do
              described_class.new(['--headless', rom_path, '--input', script_path], output:, error_output:)
            end

            before { File.write(script_path, "1: [turbo]\n") }

            it 'prints the reason and fails', :aggregate_failures do
              expect(command_line.run).to eq(1)
              expect(error_output.string).to include('"turbo"')
            end
          end

          context 'and the input script is valid' do
            subject(:command_line) do
              arguments = ['--headless', rom_path, '--frames', '2', '--screenshot', "2:#{screenshot_path}"]
              described_class.new([*arguments, '--input', script_path], output:, error_output:)
            end

            before { File.write(script_path, "1: [down]\n") }

            it 'runs the frames, writes the screenshot and prints the last digest', :aggregate_failures do
              expect(command_line.run).to eq(0)
              expect(File.binread(screenshot_path, 8)).to eq(Ruby::Nes::Frontends::Png::SIGNATURE)
              expect(output.string).to match(/\A2 frames, last frame SHA-256 \h{64}\n\z/)
            end
          end
        end
      end
    end
  end
end
