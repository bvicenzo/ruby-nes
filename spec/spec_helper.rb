# frozen_string_literal: true

if ENV['COVERAGE']
  require 'simplecov'

  SimpleCov.start do
    enable_coverage :branch
    primary_coverage :branch
    # The default "test_frameworks" profile skips all of spec/. Specs are not measured, but the test tooling in
    # spec/support/ is, so the other default profiles are reloaded and spec/ is skipped except for support/.
    filters.clear
    load_profile 'bundler_filter'
    load_profile 'hidden_filter'
    load_profile 'root_filter'
    add_filter %r{\Aspec/(?!support/)}
  end
end

require 'ruby/nes'
require_relative 'support/test_roms'

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  # Groups tagged with `test_rom:` are skipped when their ROMs have not been fetched (`rake test_roms:fetch`).
  test_rom_requirement = TestRoms::Requirement.new(manifest: TestRoms.manifest, directory: TestRoms::DIRECTORY)
  TestRoms::ExampleGroups.install(config, requirement: test_rom_requirement)

  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.order = :random
  Kernel.srand config.seed
end
