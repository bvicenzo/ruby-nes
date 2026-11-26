# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'stringio'
require 'tmpdir'
require 'ruby/nes/command_line'

# `ruby-nes ROM` (plan 16, decision 7; plan 18): enables the JIT asked, prints it, loads the ROM and runs it in the
# window, or with --headless in the headless frontend, which prints the frame count and the last frame's digest.
# `ruby-nes` with no path, or with a folder, browses the ROMs in the window instead (plan 37). The
# exit status is 0 when the run completes, 1 with a message on the error output otherwise. The JIT and the window are
# injected, so no spec enables a JIT in its own process or opens a window: here stand-ins for both.
RSpec.describe Ruby::Nes::CommandLine do
  describe '#run' do
    let(:output) { StringIO.new }
    let(:error_output) { StringIO.new }
    let(:window) { instance_double(Ruby::Nes::CommandLine::Window, run: nil, browse: nil) }

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

        context 'and no path is given' do
          context 'but the browser cannot run' do
            subject(:command_line) { described_class.new([], output:, error_output:, jit:, window:) }

            before { allow(window).to receive(:browse).and_raise(Errno::ENOENT, 'roms') }

            it 'prints the reason and fails', :aggregate_failures do
              expect(command_line.run).to eq(1)
              expect(error_output.string).to include('roms')
            end
          end

          context 'and the browser ends' do
            subject(:command_line) { described_class.new(%w[--scale 2], output:, error_output:, jit:, window:) }

            it 'browses the ROMs in the window, prints the JIT and succeeds', :aggregate_failures do
              expect(command_line.run).to eq(0)
              expect(window).to have_received(:browse).with(an_object_having_attributes(scale: 2), jit_name: 'yjit')
              expect(output.string).to eq("JIT: yjit\n")
            end
          end
        end

        context 'and a folder is given' do
          context 'but the browser cannot run' do
            subject(:command_line) { described_class.new([directory], output:, error_output:, jit:, window:) }

            before do
              allow(window).to receive(:browse)
                .and_raise(Ruby::Nes::Frontends::KeyConfig::InvalidConfig, 'not actions: turbo')
            end

            it 'prints the reason and fails', :aggregate_failures do
              expect(command_line.run).to eq(1)
              expect(error_output.string).to include('not actions: turbo')
            end
          end

          context 'and the browser ends' do
            subject(:command_line) { described_class.new([directory], output:, error_output:, jit:, window:) }

            it 'browses its ROMs in the window, prints the JIT and succeeds', :aggregate_failures do
              expect(command_line.run).to eq(0)
              expect(window).to have_received(:browse)
                .with(an_object_having_attributes(path: directory), jit_name: 'yjit')
              expect(output.string).to eq("JIT: yjit\n")
            end
          end
        end

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
              context 'and no WAV file is asked' do
                subject(:command_line) do
                  described_class.new(['--headless', rom_path, '--frames', '1'], output:, error_output:, jit:, window:)
                end

                it 'runs the frames and prints the JIT and the last digest', :aggregate_failures do
                  expect(command_line.run).to eq(0)
                  expect(output.string).to match(/\AJIT: yjit\n1 frames, last frame SHA-256 \h{64}\n\z/)
                end
              end

              context 'and a WAV file is asked' do
                let(:wav_path) { File.join(directory, 'run.wav') }

                context 'but the run fails' do
                  subject(:command_line) do
                    arguments = ['--headless', rom_path, '--frames', '2', '--wav', wav_path]
                    arguments += ['--screenshot', "2:#{missing_directory_path}"]
                    described_class.new(arguments, output:, error_output:, jit:, window:)
                  end

                  let(:missing_directory_path) { File.join(directory, 'missing', 'second.png') }

                  it 'writes the audio of the frames run, prints the reason and fails', :aggregate_failures do
                    expect(command_line.run).to eq(1)
                    expect(File.size(wav_path)).to be_within(8).of(44 + (2 * 799 * 2))
                    expect(error_output.string).to include('second.png')
                  end
                end

                context 'and the run ends' do
                  subject(:command_line) do
                    arguments = ['--headless', rom_path, '--frames', '1', '--wav', wav_path]
                    described_class.new(arguments, output:, error_output:, jit:, window:)
                  end

                  # A frame at 48 kHz and "60.0988 Hz" (https://www.nesdev.org/wiki/Cycle_reference_chart): about 799
                  # samples of 2 bytes, after the 44-byte header.
                  it "writes the frame's audio as a WAV file", :aggregate_failures do
                    expect(command_line.run).to eq(0)
                    expect(File.binread(wav_path, 4)).to eq('RIFF')
                    expect(File.size(wav_path)).to be_within(4).of(44 + (799 * 2))
                  end
                end
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

        context 'and the ROM is a battery game with a save' do
          let(:rom_path) { File.join(directory, 'game.nes') }
          let(:save_path) { File.join(directory, 'ruby-nes', 'saves', 'game.sav') }

          before do
            # LDA #$11, STA $6000, then JMP to itself: a run that kept saves would write $11 over the save.
            program = Cartridges.with_program([0xA9, 0x11, 0x8D, 0x00, 0x60, 0x4C, 0x05, 0x80])
            File.binwrite(rom_path, Cartridges.ines_image(prg_rom: program.prg_rom, battery: true))
            FileUtils.mkdir_p(File.dirname(save_path))
            File.binwrite(save_path, "\x77" * 8_192)
            stub_const('ENV', ENV.to_h.merge('XDG_DATA_HOME' => directory))
          end

          context 'and --headless is given' do
            subject(:command_line) do
              described_class.new(['--headless', rom_path, '--frames', '2'], output:, error_output:, jit:, window:)
            end

            it 'leaves the save as it was, writing no other file', :aggregate_failures do
              expect(command_line.run).to eq(0)
              expect(File.binread(save_path)).to eq("\x77" * 8_192)
              expect(Dir.children(File.dirname(save_path))).to eq(['game.sav'])
            end
          end
        end

        context 'and the ROM is the Super Mario Bros. 3 dump', :slow, local_rom: 'smb3.nes' do
          # The title screen is silent: the game first writes the channels after Start (frame 521, the menu's sound),
          # and the world map music starts at frame 588. A 1200-frame run with this input, whose first 720 frames are
          # these, was heard and judged right on 2026-11-22 (plan 24); the digest guards it.
          subject(:command_line) do
            arguments = [local_rom_path('smb3.nes'), '--headless', '--frames', '720', '--input', script_path]
            described_class.new([*arguments, '--wav', wav_path], output:, error_output:, jit:, window:)
          end

          let(:script_path) { File.join(directory, 'start.yml') }
          let(:wav_path) { File.join(directory, 'smb3.wav') }

          before { File.write(script_path, "450: [start]\n456: []\n520: [start]\n526: []\n") }

          it "writes the menu's sound and the world map music as the WAV heard" do
            command_line.run

            expect(Digest::SHA256.file(wav_path).hexdigest)
              .to eq('11c3681a3347f582efb2a3e88c1322c03508c08ebc25beec73a54b7e6f504193')
          end
        end
      end
    end
  end
end
