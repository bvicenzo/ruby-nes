# frozen_string_literal: true

require 'fileutils'
require 'stringio'
require 'tmpdir'
require 'ruby/nes/command_line'

# The window of `ruby-nes` without --headless (plan 18): the key config is read and checked before any window opens,
# actions it leaves without a key are named on the error output, and the window is closed however its run ends. The
# window is opened by an injected callable (the raylib one by default, CommandLine::RaylibWindow): here a stand-in that
# hands over a stand-in frontend.
#
# `ruby-nes ROM` plays one game in it (CommandLine::Game): the game's battery save (plan 34) is loaded before the window
# opens, so a refused save opens no window, and written when the game is closed, before the window closes.
#
# `ruby-nes [FOLDER]` opens the ROM browser in it (plan 37, CommandLine::Browser) on the ROMs of the folder named on
# the command line, else the config's `roms_directory:`, its `~` expanded, else `roms` under the current directory; a
# folder that cannot be read opens no window.
RSpec.describe Ruby::Nes::CommandLine::Window do
  describe '#run' do
    subject(:window) { described_class.new(open_window:, default_config_path:, error_output:, saves_directory:) }

    let(:directory) { Dir.mktmpdir }
    let(:default_config_path) { File.join(directory, 'default.yml') }
    let(:config_path) { File.join(directory, 'keys.yml') }
    let(:options) do
      Ruby::Nes::CommandLine::Options.parse(
        ['game.nes', '--config', config_path, '--scale', '2', '--aspect', '8:7', '--crop-overscan']
      )
    end
    let(:error_output) { StringIO.new }
    let(:saves_directory) { Ruby::Nes::Saves::Directory.new(environment: { 'XDG_DATA_HOME' => directory }) }

    after { FileUtils.remove_entry(directory) }

    context 'when the key config cannot be read' do
      let(:open_window) { instance_double(Proc, call: nil) }
      let(:console) { instance_double(Ruby::Nes::Console) }

      it 'raises, opening no window', :aggregate_failures do
        expect { window.run(console, options, jit_name: 'yjit') }.to raise_error(Errno::ENOENT)
        expect(open_window).not_to have_received(:call)
      end
    end

    context 'when the key config can be read' do
      context 'but it is invalid' do
        let(:open_window) { instance_double(Proc, call: nil) }
        let(:console) { instance_double(Ruby::Nes::Console) }

        before { File.write(config_path, "keys:\n  turbo: t\n") }

        it 'raises InvalidConfig, opening no window', :aggregate_failures do
          expect { window.run(console, options, jit_name: 'yjit') }
            .to raise_error(Ruby::Nes::Frontends::KeyConfig::InvalidConfig, /turbo/)
          expect(open_window).not_to have_received(:call)
        end
      end

      context 'and it is valid' do
        context "but the game's battery save is refused" do
          let(:open_window) { instance_double(Proc, call: nil) }
          let(:console) { instance_double(Ruby::Nes::Console) }
          let(:game) { instance_double(Ruby::Nes::CommandLine::Game, close: nil) }

          before do
            File.write(config_path, "keys:\n  pause: space\n")
            allow(Ruby::Nes::CommandLine::Game).to receive(:new).and_return(game)
            allow(game).to receive(:load).and_raise(Ruby::Nes::Saves::InvalidSave, 'game.sav has 3 bytes')
          end

          it 'raises InvalidSave, opening no window', :aggregate_failures do
            expect { window.run(console, options, jit_name: 'yjit') }
              .to raise_error(Ruby::Nes::Saves::InvalidSave, 'game.sav has 3 bytes')
            expect(open_window).not_to have_received(:call)
          end
        end

        context "and the game's battery save is loaded" do
          context 'but the window cannot be opened' do
            let(:open_window) { instance_double(Proc) }
            let(:console) { instance_double(Ruby::Nes::Console) }
            let(:game) { instance_double(Ruby::Nes::CommandLine::Game, load: nil, close: nil) }

            before do
              File.write(config_path, "keys:\n  pause: space\n")
              allow(Ruby::Nes::CommandLine::Game).to receive(:new).and_return(game)
              allow(open_window).to receive(:call).and_raise(Ruby::Nes::Error, 'the raylib library is missing')
            end

            it 'raises the reason' do
              expect { window.run(console, options, jit_name: 'yjit') }
                .to raise_error(Ruby::Nes::Error, 'the raylib library is missing')
            end
          end

          context 'and the window opens' do
            context 'but the game fails' do
              let(:open_window) { instance_double(Proc, call: frontend) }
              let(:frontend) { instance_double(Ruby::Nes::Frontends::Base, close: nil) }
              let(:console) { instance_double(Ruby::Nes::Console) }
              let(:game) { instance_double(Ruby::Nes::CommandLine::Game, load: nil, close: nil) }

              before do
                File.write(config_path, "keys:\n  pause: space\n")
                allow(Ruby::Nes::CommandLine::Game).to receive(:new).and_return(game)
                allow(game).to receive(:play).and_raise(Ruby::Nes::Error, 'the window crashed')
              end

              it 'closes the game and the window', :aggregate_failures do
                expect { window.run(console, options, jit_name: 'yjit') }.to raise_error(Ruby::Nes::Error)
                expect(game).to have_received(:close)
                expect(frontend).to have_received(:close)
              end
            end

            context 'but the game cannot write its battery save as it closes' do
              let(:open_window) { instance_double(Proc, call: frontend) }
              let(:frontend) { instance_double(Ruby::Nes::Frontends::Base, close: nil) }
              let(:console) { instance_double(Ruby::Nes::Console) }
              let(:game) { instance_double(Ruby::Nes::CommandLine::Game, load: nil, play: nil) }

              before do
                File.write(config_path, "keys:\n  pause: space\n")
                allow(Ruby::Nes::CommandLine::Game).to receive(:new).and_return(game)
                allow(game).to receive(:close).and_raise(Errno::EACCES, 'game.sav')
              end

              it 'raises, closing the window', :aggregate_failures do
                expect { window.run(console, options, jit_name: 'yjit') }.to raise_error(Errno::EACCES)
                expect(frontend).to have_received(:close)
              end
            end

            context 'and the game ends' do
              context 'and every action has a key' do
                let(:open_window) { instance_double(Proc, call: frontend) }
                let(:frontend) { instance_double(Ruby::Nes::Frontends::Base, close: nil) }
                let(:console) { instance_double(Ruby::Nes::Console) }
                let(:game) { instance_double(Ruby::Nes::CommandLine::Game, load: nil, play: nil, close: nil) }

                before do
                  config = "keys:\n  pause: space\ngamepad:\n  a: right_trigger_1\ngamepad_mappings: 0300,Pad\n"
                  File.write(config_path, config)
                  allow(Ruby::Nes::CommandLine::Game).to receive(:new).and_return(game)
                  window.run(console, options, jit_name: 'zjit')
                end

                it 'opens it with the keys, the gamepad config, the viewport, the JIT and the audio' do
                  expect(open_window).to have_received(:call).with(
                    keys: a_hash_including(pause: ['space'], a: ['x']),
                    gamepad_buttons: a_hash_including(a: ['right_trigger_1'], start: ['middle_right']),
                    gamepad_mappings: '0300,Pad',
                    viewport: an_object_having_attributes(width: 585, height: 448),
                    jit_name: 'zjit',
                    audio: true
                  )
                end

                it "plays the ROM's game in it, its saves in the saves directory", :aggregate_failures do
                  expect(Ruby::Nes::CommandLine::Game).to have_received(:new)
                    .with(console:, rom_path: 'game.nes', directory: saves_directory, error_output:)
                  expect(game).to have_received(:play).with(frontend)
                end

                it 'closes the game, then the window', :aggregate_failures do
                  expect(game).to have_received(:close).ordered
                  expect(frontend).to have_received(:close).ordered
                end

                it 'warns about nothing' do
                  expect(error_output.string).to be_empty
                end
              end

              context 'and an action is left without a key' do
                let(:open_window) { instance_double(Proc, call: frontend) }
                let(:frontend) { instance_double(Ruby::Nes::Frontends::Base, close: nil) }
                let(:console) { instance_double(Ruby::Nes::Console) }
                let(:game) { instance_double(Ruby::Nes::CommandLine::Game, load: nil, play: nil, close: nil) }

                before do
                  File.write(config_path, "keys:\n  a: z\n")
                  allow(Ruby::Nes::CommandLine::Game).to receive(:new).and_return(game)
                  window.run(console, options, jit_name: 'zjit')
                end

                it 'warns naming it' do
                  expect(error_output.string).to eq("ruby-nes: no key for b\n")
                end
              end
            end
          end
        end
      end
    end
  end

  describe '#browse' do
    subject(:window) { described_class.new(open_window:, default_config_path:, error_output:, saves_directory:) }

    let(:directory) { Dir.mktmpdir }
    let(:default_config_path) { File.join(directory, 'default.yml') }
    let(:config_path) { File.join(directory, 'keys.yml') }
    let(:error_output) { StringIO.new }
    let(:saves_directory) { Ruby::Nes::Saves::Directory.new(environment: { 'XDG_DATA_HOME' => directory }) }

    after { FileUtils.remove_entry(directory) }

    context 'when the key config cannot be read' do
      let(:open_window) { instance_double(Proc, call: nil) }
      let(:options) { Ruby::Nes::CommandLine::Options.parse(['--config', config_path]) }

      it 'raises, opening no window', :aggregate_failures do
        expect { window.browse(options, jit_name: 'yjit') }.to raise_error(Errno::ENOENT)
        expect(open_window).not_to have_received(:call)
      end
    end

    context 'when the key config is valid' do
      context "but its folder is under the home of a user who doesn't exist" do
        let(:open_window) { instance_double(Proc, call: nil) }
        let(:options) { Ruby::Nes::CommandLine::Options.parse(['--config', config_path]) }

        before { File.write(config_path, "roms_directory: ~nobody-at-all/roms\n") }

        it 'raises InvalidConfig naming the section, opening no window', :aggregate_failures do
          expect { window.browse(options, jit_name: 'yjit') }
            .to raise_error(Ruby::Nes::Frontends::KeyConfig::InvalidConfig, /roms_directory: .*nobody-at-all/)
          expect(open_window).not_to have_received(:call)
        end
      end

      context 'but the folder cannot be read' do
        let(:open_window) { instance_double(Proc, call: nil) }
        let(:options) { Ruby::Nes::CommandLine::Options.parse([File.join(directory, 'roms'), '--config', config_path]) }

        before { File.write(config_path, "keys:\n  pause: space\n") }

        it 'raises, opening no window', :aggregate_failures do
          expect { window.browse(options, jit_name: 'yjit') }.to raise_error(Errno::ENOENT)
          expect(open_window).not_to have_received(:call)
        end
      end

      context 'and the folder can be read' do
        context 'but the browser fails' do
          let(:open_window) { instance_double(Proc, call: frontend) }
          let(:frontend) { instance_double(Ruby::Nes::Frontends::Base, close: nil) }
          let(:options) { Ruby::Nes::CommandLine::Options.parse([directory, '--config', config_path]) }
          let(:browser) { instance_double(Ruby::Nes::CommandLine::Browser) }

          before do
            File.write(config_path, "keys:\n  pause: space\n")
            allow(Ruby::Nes::CommandLine::Browser).to receive(:new).and_return(browser)
            allow(browser).to receive(:run).and_raise(Ruby::Nes::Error, 'the window crashed')
          end

          it 'closes the window', :aggregate_failures do
            expect { window.browse(options, jit_name: 'yjit') }.to raise_error(Ruby::Nes::Error)
            expect(frontend).to have_received(:close)
          end
        end

        context 'and the command line names it' do
          let(:open_window) { instance_double(Proc, call: frontend) }
          let(:frontend) { instance_double(Ruby::Nes::Frontends::Base, close: nil) }
          let(:folder) { File.join(directory, 'games') }
          let(:options) { Ruby::Nes::CommandLine::Options.parse([folder, '--config', config_path, '--no-audio']) }
          let(:browser) { instance_double(Ruby::Nes::CommandLine::Browser, run: nil) }

          before do
            File.write(config_path, "keys:\n  pause: space\nroms_directory: #{File.join(directory, 'other')}\n")
            FileUtils.mkdir_p(folder)
            File.binwrite(File.join(folder, 'Zelda.nes'), Cartridges.ines_image(prg_rom: Array.new(16_384, 0)))
            allow(Ruby::Nes::CommandLine::Browser).to receive(:new).and_return(browser)
            window.browse(options, jit_name: 'yjit')
          end

          it 'browses its ROMs in the window, the games sounding as the options say', :aggregate_failures do
            expect(Ruby::Nes::CommandLine::Browser).to have_received(:new).with(
              frontend:,
              folder:,
              roms: [an_object_having_attributes(path: File.join(folder, 'Zelda.nes'))],
              directory: saves_directory,
              audio_sample_rate: nil,
              error_output:
            )
            expect(browser).to have_received(:run)
          end

          it 'closes the window' do
            expect(frontend).to have_received(:close)
          end
        end

        context 'and only the config names it' do
          let(:open_window) { instance_double(Proc, call: frontend) }
          let(:frontend) { instance_double(Ruby::Nes::Frontends::Base, close: nil) }
          let(:options) { Ruby::Nes::CommandLine::Options.parse(['--config', config_path]) }
          let(:browser) { instance_double(Ruby::Nes::CommandLine::Browser, run: nil) }

          before do
            File.write(config_path, "roms_directory: ~/games/nes\n")
            allow(Ruby::Nes::Frontends::Browser::RomList).to receive(:scan).and_return([])
            allow(Ruby::Nes::CommandLine::Browser).to receive(:new).and_return(browser)
            window.browse(options, jit_name: 'yjit')
          end

          it 'browses the ROMs of the folder the config names, its ~ expanded' do
            expect(Ruby::Nes::CommandLine::Browser).to have_received(:new)
              .with(a_hash_including(folder: File.join(Dir.home, 'games', 'nes')))
          end
        end

        context 'and neither names it' do
          let(:open_window) { instance_double(Proc, call: frontend) }
          let(:frontend) { instance_double(Ruby::Nes::Frontends::Base, close: nil) }
          let(:options) { Ruby::Nes::CommandLine::Options.parse(['--config', config_path]) }
          let(:browser) { instance_double(Ruby::Nes::CommandLine::Browser, run: nil) }

          before do
            File.write(config_path, "keys:\n  pause: space\n")
            FileUtils.mkdir_p(File.join(directory, 'roms'))
            allow(Ruby::Nes::CommandLine::Browser).to receive(:new).and_return(browser)
            Dir.chdir(directory) { window.browse(options, jit_name: 'yjit') }
          end

          it 'browses the ROMs of roms under the current directory' do
            expect(Ruby::Nes::CommandLine::Browser).to have_received(:new)
              .with(a_hash_including(folder: File.join(File.realpath(directory), 'roms')))
          end
        end
      end
    end
  end
end
