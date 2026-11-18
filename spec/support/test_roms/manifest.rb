# frozen_string_literal: true

require 'yaml'

module TestRoms
  # A path that the manifest does not list: a typo in a spec's `test_rom:` metadata, never a ROM to skip.
  class UnknownRomError < StandardError; end

  # The list of test ROMs the suite uses: the pinned commit of the collection, the sources serving it (tried in
  # order; any of them serves the same bytes, verified by checksum), and the files.
  Manifest = Data.define(:commit, :sources, :entries) do
    def self.load(file_path)
      manifest_document = YAML.safe_load_file(file_path)
      entries = manifest_document.fetch('files').map { |path, checksum| Entry.new(path:, checksum:) }

      new(commit: manifest_document.fetch('commit'), sources: manifest_document.fetch('sources'), entries:)
    end

    def find(path)
      entries.find { |entry| entry.path == path } or raise UnknownRomError, "#{path} is not listed in the manifest"
    end

    def urls_for(entry) = sources.map { |source| "#{source}/#{commit}/#{entry.path}" }
  end
end
