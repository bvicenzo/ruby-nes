# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require 'ruby/nes/command_line'

# The text of the window's key config (plan 18, decision 7): the file `--config` names, which must exist, or the
# default file, ~/.config/ruby-nes/config.yml, which may not: then the text is empty and every key keeps its default.
RSpec.describe Ruby::Nes::CommandLine::ConfigFile do
  describe '.text' do
    let(:directory) { Dir.mktmpdir }
    let(:default_path) { File.join(directory, 'default.yml') }

    after { FileUtils.remove_entry(directory) }

    context 'when a path is given' do
      let(:path) { File.join(directory, 'keys.yml') }

      context 'but no file is there' do
        before { File.write(default_path, "keys:\n  a: x\n") }

        it 'raises Errno::ENOENT' do
          expect { described_class.text(path, default_path:) }.to raise_error(Errno::ENOENT, /keys\.yml/)
        end
      end

      context 'and a file is there' do
        before do
          File.write(path, "keys:\n  pause: space\n")
          File.write(default_path, "keys:\n  a: x\n")
        end

        it 'is its text' do
          expect(described_class.text(path, default_path:)).to eq("keys:\n  pause: space\n")
        end
      end
    end

    context 'when no path is given' do
      context 'and the default file is absent' do
        it 'is empty' do
          expect(described_class.text(nil, default_path:)).to eq('')
        end
      end

      context 'and the default file is there' do
        before { File.write(default_path, "keys:\n  a: x\n") }

        it 'is its text' do
          expect(described_class.text(nil, default_path:)).to eq("keys:\n  a: x\n")
        end
      end
    end
  end
end
