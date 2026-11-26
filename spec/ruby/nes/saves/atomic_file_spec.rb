# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require 'ruby/nes/saves'

# What ruby-nes keeps on disk is written whole or not at all (plan 34, decision 7; plan 35, decision 7): the bytes go
# to a temporary file of its own beside the target (a unique name, created exclusively, so two windows never write into
# each other's), flushed to the disk, then renamed over the target. A crash mid-write leaves the old file or the new
# one, never half of one.
RSpec.describe Ruby::Nes::Saves::AtomicFile do
  describe '.write' do
    let(:directory) { Dir.mktmpdir }

    after { FileUtils.remove_entry(directory) }

    context 'when the folder does not exist' do
      let(:path) { File.join(directory, 'ruby-nes', 'states', 'Zelda', '3.state') }

      it 'creates it and writes the bytes' do
        described_class.write(path) { it.write('state') }

        expect(File.binread(path)).to eq('state')
      end
    end

    context 'when the folder exists' do
      let(:path) { File.join(directory, '3.state') }

      context 'but the writing fails' do
        before { File.binwrite(path, 'older state') }

        it 'raises, keeping the older file whole and no temporary file', :aggregate_failures do
          expect { described_class.write(path) { raise IOError, 'disk full' } }.to raise_error(IOError, 'disk full')
          expect(File.binread(path)).to eq('older state')
          expect(Dir.children(directory)).to eq(['3.state'])
        end
      end

      context "and another write's temporary file is beside the target" do
        before { File.binwrite("#{path}.tmp", "half of another window's state") }

        it 'writes the bytes, leaving that file alone', :aggregate_failures do
          described_class.write(path) { it.write('state') }

          expect(File.binread(path)).to eq('state')
          expect(File.binread("#{path}.tmp")).to eq("half of another window's state")
        end
      end

      context 'and no file is there yet' do
        it 'writes the bytes, leaving no temporary file', :aggregate_failures do
          described_class.write(path) { it.write('state') }

          expect(File.binread(path)).to eq('state')
          expect(Dir.children(directory)).to eq(['3.state'])
        end
      end

      context 'and an older file is there' do
        before { File.binwrite(path, 'older state') }

        it 'replaces it with the bytes' do
          described_class.write(path) { it.write('state') }

          expect(File.binread(path)).to eq('state')
        end
      end
    end
  end
end
