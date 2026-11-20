# frozen_string_literal: true

require 'fileutils'
require 'stringio'
require 'tmpdir'
require 'ruby/nes/command_line'

# `ruby-nes ROM` (plan 16, decision 7; plan 18): enables the JIT asked, prints it, loads the ROM and runs it in the
# window, or with --headless in the headless frontend, which prints the frame count and the last frame's digest. The
# exit status is 0 when the run completes, 1 with a message on the error output otherwise. The JIT and the window are
# injected, so no spec enables a JIT in its own process or opens a window: here stand-ins for both.
RSpec.describe Ruby::Nes::CommandLine do
  describe '#run' do
    let(:output) { StringIO.new }
    let(:error_output) { StringIO.new }
    let(:window) { instance_double(Ruby::Nes::CommandLine::Window, run: nil) }

    context 'when the options are invalid' do
      subject(:command_line) { described_class.new(%w[--headless], output:, error_output:, jit:, window:) }

      let(:jit) { instance_double(Ruby::Nes::CommandLine::Jit, enable: nil, running: 'yjit') }

      it 'prints the reason and the usage to the error output and fails', :aggregate_failures do
        expect(command_line.run).to eq(1)
        expect(error_output.string).to include('missing argument: ROM', 'Usage: ruby-nes ROM')
      end
    end

    context 'when the options are valid' do
      context 'but they only ask for information' do
        subject(:command_line) { described_class.new(%w[--version], output:, error_output:, jit:, window:) }

        let(:jit) { instance_double(Ruby::Nes::CommandLine::Jit, enable: nil, running: 'yjit') }

        it 'prints it and succeeds', :aggregate_failures do
          expect(command_line.run).to eq(0)
          expect(output.string).to eq("ruby-nes #{Ruby::Nes::VERSION}\n")
        end
      end

      context 'but the JIT asked cannot run' do
        subject(:command_line) { described_class.new(%w[game.nes --jit=zjit], output:, error_output:, jit:, window:) }

        let(:jit) { instance_double(Ruby::Nes::CommandLine::Jit, running: 'yjit') }

        before do
          allow(jit).to receive(:enable)
            .with('zjit')
            .and_raise(Ruby::Nes::CommandLine::Jit::Unavailable, 'yjit is already running')
        end

        it 'prints the reason and fails', :aggregate_failures do
          expect(command_line.run).to eq(1)
          expect(error_output.string).to include('yjit is already running')
        end
      end

      context 'and the JIT runs' do
        let(:jit) { instance_double(Ruby::Nes::CommandLine::Jit, enable: nil, running: 'yjit') }
        let(:directory) { Dir.mktmpdir }

        after { FileUtils.remove_entry(directory) }

        context 'but the ROM cannot be loaded' do
          subject(:command_line) do
            described_class.new([File.join(directory, 'missing.nes')], output:, error_output:, jit:, window:)
          end

          it 'prints the reason and fails', :aggregate_failures do
            expect(command_line.run).to eq(1)
            expect(error_output.string).to include('missing.nes')
          end
        end

        context 'and the ROM loads', test_rom: Nestest::ROM_PATH do
          let(:rom_path) { test_rom_path(Nestest::ROM_PATH) }

          context 'and --headless is given' do
            let(:script_path) { File.join(directory, 'moves.yml') }
            let(:screenshot_path) { File.join(directory, 'second.png') }

            context 'and no input script is given' do
              subject(:command_line) do
                described_class.new(['--headless', rom_path, '--frames', '1'], output:, error_output:, jit:, window:)
              end

              it 'runs the frames and prints the JIT and the last digest', :aggregate_failures do
                expect(command_line.run).to eq(0)
                expect(output.string).to match(/\AJIT: yjit\n1 frames, last frame SHA-256 \h{64}\n\z/)
              end
            end

            context 'but the input script cannot be read' do
              subject(:command_line) do
                arguments = ['--headless', rom_path, '--input', script_path]
                described_class.new(arguments, output:, error_output:, jit:, window:)
              end

              it 'prints the reason and fails', :aggregate_failures do
                expect(command_line.run).to eq(1)
                expect(error_output.string).to include('moves.yml')
              end
            end

            context 'but the input script is invalid' do
              subject(:command_line) do
                arguments = ['--headless', rom_path, '--input', script_path]
                described_class.new(arguments, output:, error_output:, jit:, window:)
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
                described_class.new([*arguments, '--input', script_path], output:, error_output:, jit:, window:)
              end

              before { File.write(script_path, "1: [down]\n") }

              it 'runs the frames, writes the screenshot and prints the JIT and the last digest', :aggregate_failures do
                expect(command_line.run).to eq(0)
                expect(File.binread(screenshot_path, 8)).to eq(Ruby::Nes::Frontends::Png::SIGNATURE)
                expect(output.string).to match(/\AJIT: yjit\n2 frames, last frame SHA-256 \h{64}\n\z/)
              end
            end
          end

          context 'and --headless is not given' do
            context 'but the window cannot run' do
              subject(:command_line) { described_class.new([rom_path], output:, error_output:, jit:, window:) }

              before do
                allow(window).to receive(:run)
                  .and_raise(Ruby::Nes::Frontends::KeyConfig::InvalidConfig, 'not actions: turbo')
              end

              it 'prints the reason and fails', :aggregate_failures do
                expect(command_line.run).to eq(1)
                expect(error_output.string).to include('not actions: turbo')
              end
            end

            context 'and the window run ends' do
              subject(:command_line) do
                described_class.new([rom_path, '--scale', '2'], output:, error_output:, jit:, window:)
              end

              it 'runs the console in the window, prints the JIT and succeeds', :aggregate_failures do
                expect(command_line.run).to eq(0)
                expect(window).to have_received(:run).with(
                  an_instance_of(Ruby::Nes::Console), an_object_having_attributes(scale: 2), jit_name: 'yjit'
                )
                expect(output.string).to eq("JIT: yjit\n")
              end
            end
          end
        end
      end
    end
  end
end
