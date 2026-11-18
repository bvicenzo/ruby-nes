# frozen_string_literal: true

# Community test ROMs (nestest, blargg's suites...) fetched from a pinned commit of a collection and verified by
# checksum. They are never committed: see plans/02-test-rom-harness.md.
module TestRoms
  DIRECTORY = File.expand_path('../fixtures/test_roms', __dir__)
  MANIFEST_FILE = File.expand_path('../fixtures/test_roms.yml', __dir__)

  def self.manifest = Manifest.load(MANIFEST_FILE)
end

require_relative 'test_roms/entry'
require_relative 'test_roms/manifest'
require_relative 'test_roms/downloader'
require_relative 'test_roms/sources'
require_relative 'test_roms/fetcher'
require_relative 'test_roms/requirement'
require_relative 'test_roms/example_groups'
