# frozen_string_literal: true

require 'rspec/core/rake_task'
require_relative '../spec/support/test_roms'

namespace :test_roms do
  desc 'Download the test ROMs of spec/fixtures/test_roms.yml that are missing or corrupted, verifying checksums'
  task :fetch do
    manifest = TestRoms.manifest
    sources = TestRoms::Sources.new(manifest:, downloader: TestRoms::Downloader.new)
    fetcher = TestRoms::Fetcher.new(entries: manifest.entries, directory: TestRoms::DIRECTORY, sources:)

    fetcher.fetch { |path, outcome| puts "#{outcome.to_s.tr('_', ' ')}: #{path}" }
  rescue TestRoms::FetchError => error
    abort error.message
  end
end

namespace :spec do
  desc 'Run only the specs that need test ROMs (tagged with test_rom:)'
  RSpec::Core::RakeTask.new(:test_roms) { |task| task.rspec_opts = '--tag test_rom' }
end
