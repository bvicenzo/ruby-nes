# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require 'ruby/nes/command_line'

# A battery save on disk (plan 34): the raw 8 KiB of the cartridge's battery-backed PRG RAM, as other emulators keep
# it. A missing file is no save yet; a file of another size is refused, never loaded or overwritten (decision 5).
# Writes are atomic (decision 7): the bytes go to a temporary file of its own beside the save, which is renamed over it,
# so two windows of the same game never write into each other's.
RSpec.describe Ruby::Nes::Saves::BatteryFile do
  describe '#read' do
    subject(:file) { described_class.new(path) }

    let(:directory) { Dir.mktmpdir }
    let(:path) { File.join(directory, 'Zelda.sav') }

    after { FileUtils.remove_entry(directory) }

    context 'when the file does not exist' do
      it 'is nil' do
        expect(file.read).to be_nil
      end
    end

    context 'when the file exists' do
      context 'but it cannot be read' do
        before { Dir.mkdir(path) }

        it 'raises the system error' do
          expect { file.read }.to raise_error(SystemCallError)
        end
      end

      context 'but it is shorter than 8 KiB' do
        before { File.binwrite(path, "\x00" * 8_191) }

        it 'raises InvalidSave naming the file and both sizes' do
          expect { file.read }.to raise_error(Ruby::Nes::Saves::InvalidSave, /Zelda\.sav.*8191.*8192/)
        end
      end

      context 'but it is longer than 8 KiB' do
        before { File.binwrite(path, "\x00" * 8_193) }

        it 'raises InvalidSave naming the file and both sizes' do
          expect { file.read }.to raise_error(Ruby::Nes::Saves::InvalidSave, /Zelda\.sav.*8193.*8192/)
        end
      end

      context 'and it is 8 KiB' do
        before { File.binwrite(path, "\x11#{"\x00" * 8_190}\x22") }

        it 'is its bytes, the first one first' do
          expect(file.read).to eq([0x11, *Array.new(8_190, 0x00), 0x22])
        end
      end
    end
  end

  describe '#write' do
    subject(:file) { described_class.new(path) }

    let(:directory) { Dir.mktmpdir }
    let(:save) { [0x11, *Array.new(8_190, 0x00), 0x22] }

    after { FileUtils.remove_entry(directory) }

    context 'when the folder does not exist' do
      let(:path) { File.join(directory, 'ruby-nes', 'saves', 'Zelda.sav') }

      it 'creates it and writes the bytes' do
        file.write(save)

        expect(File.binread(path).bytes).to eq(save)
      end
    end

    context 'when the folder exists' do
      let(:path) { File.join(directory, 'Zelda.sav') }

      context 'but the bytes cannot be written' do
        let(:older_save) { "\x33" * 8_192 }

        before { File.binwrite(path, older_save) }

        it 'raises, keeping the older save whole and no temporary file', :aggregate_failures do
          expect { file.write([0x11, nil]) }.to raise_error(TypeError)
          expect(File.binread(path)).to eq(older_save)
          expect(Dir.children(directory)).to eq(['Zelda.sav'])
        end
      end

      context 'and another write\'s temporary file is beside the save' do
        before { File.binwrite("#{path}.tmp", 'half of another window\'s save') }

        it 'writes the save, leaving that file alone', :aggregate_failures do
          file.write(save)

          expect(File.binread(path).bytes).to eq(save)
          expect(File.binread("#{path}.tmp")).to eq('half of another window\'s save')
        end
      end

      context 'and no save is there yet' do
        it 'writes the bytes, leaving no temporary file', :aggregate_failures do
          file.write(save)

          expect(File.binread(path).bytes).to eq(save)
          expect(Dir.children(directory)).to eq(['Zelda.sav'])
        end
      end

      context 'and an older save is there' do
        before { File.binwrite(path, "\x33" * 8_192) }

        it 'replaces it with the bytes' do
          file.write(save)

          expect(File.binread(path).bytes).to eq(save)
        end
      end
    end
  end
end
