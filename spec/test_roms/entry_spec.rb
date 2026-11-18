# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'tmpdir'

RSpec.describe TestRoms::Entry do
  describe '#local_path' do
    subject(:entry) { described_class.new(path: 'other/nestest.nes', checksum: Digest::SHA256.hexdigest('rom')) }

    it 'places the collection path under the directory' do
      expect(entry.local_path('/fixtures/test_roms')).to eq('/fixtures/test_roms/other/nestest.nes')
    end
  end

  describe '#matching?' do
    subject(:entry) { described_class.new(path: 'other/nestest.nes', checksum:) }

    let(:expected_content) { "\x4E\x45\x53\x1A\x01".b }
    let(:checksum) { Digest::SHA256.hexdigest(expected_content) }

    context 'when the content digest differs from the checksum' do
      let(:corrupted_content) { "\x4E\x45\x53\x1A\x02".b }

      it { expect(entry).not_to be_matching(corrupted_content) }
    end

    context 'when the content digest equals the checksum' do
      it { expect(entry).to be_matching(expected_content.dup) }
    end
  end

  describe '#intact_in?' do
    subject(:entry) { described_class.new(path: 'other/nestest.nes', checksum:) }

    let(:expected_content) { "\x4E\x45\x53\x1A\x01".b }
    let(:checksum) { Digest::SHA256.hexdigest(expected_content) }
    let(:directory) { Dir.mktmpdir }
    let(:file_path) { File.join(directory, 'other/nestest.nes') }

    after { FileUtils.remove_entry(directory) }

    context 'when the file is missing' do
      it { expect(entry).not_to be_intact_in(directory) }

      it 'does not create the file' do
        entry.intact_in?(directory)

        expect(File).not_to exist(file_path)
      end
    end

    context 'when the file exists' do
      before do
        FileUtils.mkdir_p(File.dirname(file_path))
        File.binwrite(file_path, stored_content)
      end

      context 'but its content differs from the checksum' do
        let(:stored_content) { "\x4E\x45\x53\x1A".b }

        it { expect(entry).not_to be_intact_in(directory) }

        it 'leaves the file untouched' do
          entry.intact_in?(directory)

          expect(File.binread(file_path)).to eq(stored_content)
        end
      end

      context 'and its content matches the checksum' do
        let(:stored_content) { expected_content }

        it { expect(entry).to be_intact_in(directory) }
      end
    end
  end
end
