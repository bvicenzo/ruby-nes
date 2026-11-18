# frozen_string_literal: true

# nestest (other/nestest.nes in the test ROM collection) run in automation mode and compared with its reference trace,
# other/nestest.log: see plans/08-nestest-trace-official.md. Test tooling, required by the specs and rakelib/.
module Nestest
  # Paths in the test ROM manifest (spec/fixtures/test_roms.yml).
  ROM_PATH = 'other/nestest.nes'
  LOG_PATH = 'other/nestest.log'
end

require_relative 'nestest/log'
require_relative 'nestest/divergence'
require_relative 'nestest/runner'
