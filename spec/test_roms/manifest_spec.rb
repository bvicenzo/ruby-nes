# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'

RSpec.describe TestRoms::Manifest do
  describe '.load' do
    let(:directory) { Dir.mktmpdir }
    let(:manifest_file) { File.join(directory, 'test_roms.yml') }

    before { File.write(manifest_file, manifest_yaml) }

    after { FileUtils.remove_entry(directory) }

    context 'when the commit is missing' do
      let(:manifest_yaml) do
        <<~YAML
          sources:
            - https://upstream.example/roms
          files:
            other/nestest.nes: aaaa
        YAML
      end

      it { expect { described_class.load(manifest_file) }.to raise_error(KeyError, /commit/) }
    end

    context 'when the sources are missing' do
      let(:manifest_yaml) do
        <<~YAML
          commit: 95d8f621
          files:
            other/nestest.nes: aaaa
        YAML
      end

      it { expect { described_class.load(manifest_file) }.to raise_error(KeyError, /sources/) }
    end

    context 'when the files are missing' do
      let(:manifest_yaml) do
        <<~YAML
          commit: 95d8f621
          sources:
            - https://upstream.example/roms
        YAML
      end

      it { expect { described_class.load(manifest_file) }.to raise_error(KeyError, /files/) }
    end

    context 'when every key is present' do
      let(:manifest_yaml) do
        <<~YAML
          commit: 95d8f621
          sources:
            - https://upstream.example/roms
            - https://mirror.example/roms
          files:
            other/nestest.nes: aaaa
            other/nestest.log: bbbb
        YAML
      end

      let(:expected_sources) { ['https://upstream.example/roms', 'https://mirror.example/roms'] }
      let(:expected_entries) do
        [
          TestRoms::Entry.new(path: 'other/nestest.nes', checksum: 'aaaa'),
          TestRoms::Entry.new(path: 'other/nestest.log', checksum: 'bbbb')
        ]
      end

      it 'reads the commit, the sources in order, and one entry per file' do
        expect(described_class.load(manifest_file))
          .to have_attributes(commit: '95d8f621', sources: expected_sources, entries: expected_entries)
      end
    end
  end

  describe '#find' do
    subject(:manifest) do
      described_class.new(commit: '95d8f621', sources: ['https://upstream.example/roms'], entries: [nestest])
    end

    let(:nestest) { TestRoms::Entry.new(path: 'other/nestest.nes', checksum: 'aaaa') }

    context 'when the path is not listed' do
      it do
        expect { manifest.find('other/nestest.txt') }
          .to raise_error(TestRoms::UnknownRomError, %r{other/nestest\.txt})
      end
    end

    context 'when the path is listed' do
      it { expect(manifest.find('other/nestest.nes')).to eq(nestest) }
    end
  end

  describe '#urls_for' do
    subject(:manifest) { described_class.new(commit: '95d8f621', sources:, entries: [nestest]) }

    let(:sources) { ['https://upstream.example/roms', 'https://mirror.example/roms'] }
    let(:nestest) { TestRoms::Entry.new(path: 'other/nestest.nes', checksum: 'aaaa') }

    let(:expected_urls) do
      [
        'https://upstream.example/roms/95d8f621/other/nestest.nes',
        'https://mirror.example/roms/95d8f621/other/nestest.nes'
      ]
    end

    it 'returns one URL per source, in source order, at the pinned commit' do
      expect(manifest.urls_for(nestest)).to eq(expected_urls)
    end
  end
end
