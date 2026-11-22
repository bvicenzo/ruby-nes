# frozen_string_literal: true

require 'fileutils'
require 'stringio'
require 'tmpdir'
require 'ruby/nes/command_line'

# `ruby-nes ROM` without --headless (plan 18): the key config is read and checked before any window opens, actions it
# leaves without a key are named on the error output, then the console runs in the window, through Frontends::Driver,
# until the window stops; the window is closed however the run ends. The window is opened by an injected callable (the raylib one by default, CommandLine::RaylibWindow): here a
# stand-in that hands over a stand-in frontend.
RSpec.describe Ruby::Nes::CommandLine::Window do
  describe '#run' do
    subject(:window) { described_class.new(open_window:, default_config_path:, error_output:) }

    let(:directory) { Dir.mktmpdir }
    let(:default_config_path) { File.join(directory, 'default.yml') }
    let(:config_path) { File.join(directory, 'keys.yml') }
    let(:options) do
      Ruby::Nes::CommandLine::Options.parse(
        ['game.nes', '--config', config_path, '--scale', '2', '--aspect', '8:7', '--crop-overscan']
      )
    end
    let(:console) { instance_double(Ruby::Nes::Console) }
    let(:error_output) { StringIO.new }

    after { FileUtils.remove_entry(directory) }

    context 'when the key config cannot be read' do
      let(:open_window) { instance_double(Proc, call: nil) }

      it 'raises, opening no window', :aggregate_failures do
        expect { window.run(console, options, jit_name: 'yjit') }.to raise_error(Errno::ENOENT)
        expect(open_window).not_to have_received(:call)
      end
    end

    context 'when the key config can be read' do
      context 'but it is invalid' do
        let(:open_window) { instance_double(Proc, call: nil) }

        before { File.write(config_path, "keys:\n  turbo: t\n") }

        it 'raises InvalidConfig, opening no window', :aggregate_failures do
          expect { window.run(console, options, jit_name: 'yjit') }
            .to raise_error(Ruby::Nes::Frontends::KeyConfig::InvalidConfig, /turbo/)
          expect(open_window).not_to have_received(:call)
        end
      end

      context 'and it is valid' do
        context 'but the window cannot be opened' do
          let(:open_window) { instance_double(Proc) }

          before do
            File.write(config_path, "keys:\n  pause: space\n")
            allow(open_window).to receive(:call).and_raise(Ruby::Nes::Error, 'the raylib library is missing')
          end

          it 'raises the reason' do
            expect { window.run(console, options, jit_name: 'yjit') }
              .to raise_error(Ruby::Nes::Error, 'the raylib library is missing')
          end
        end

        context 'and the window opens' do
          context 'but the run fails' do
            let(:open_window) { instance_double(Proc, call: frontend) }
            let(:frontend) { instance_double(Ruby::Nes::Frontends::Base, close: nil) }

            before do
              File.write(config_path, "keys:\n  pause: space\n")
              allow(frontend).to receive(:running?).and_raise(Ruby::Nes::Error, 'the window crashed')
            end

            it 'closes the window', :aggregate_failures do
              expect { window.run(console, options, jit_name: 'yjit') }.to raise_error(Ruby::Nes::Error)
              expect(frontend).to have_received(:close)
            end
          end

          context 'and the run ends' do
            let(:open_window) { instance_double(Proc, call: frontend) }
            let(:frontend) { instance_double(Ruby::Nes::Frontends::Base, running?: false, close: nil) }

            context 'and every action has a key' do
              before do
                File.write(config_path, "keys:\n  pause: space\n")
                window.run(console, options, jit_name: 'zjit')
              end

              it 'opens it with the keys, the viewport, the JIT and the audio' do
                expect(open_window).to have_received(:call).with(
                  keys: a_hash_including(pause: ['space'], a: ['x']),
                  viewport: an_object_having_attributes(width: 585, height: 448),
                  jit_name: 'zjit',
                  audio: true
                )
              end

              it 'closes the window' do
                expect(frontend).to have_received(:close)
              end

              it 'warns about nothing' do
                expect(error_output.string).to be_empty
              end
            end

            context 'and an action is left without a key' do
              before do
                File.write(config_path, "keys:\n  a: z\n")
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
