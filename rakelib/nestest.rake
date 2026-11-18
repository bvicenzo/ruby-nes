# frozen_string_literal: true

namespace :nestest do
  desc 'Run nestest in automation mode and print the first official line that differs from nestest.log'
  task :diff do
    # Loaded here, not at the top: other rake tasks (build, rubocop) must not depend on the emulator loading.
    require_relative '../lib/ruby/nes'
    require_relative '../spec/support/test_roms'
    require_relative '../spec/support/nestest'

    requirement = TestRoms.requirement
    unavailable_reason = requirement.skip_reason([Nestest::ROM_PATH, Nestest::LOG_PATH])
    abort unavailable_reason if unavailable_reason

    cartridge = Ruby::Nes::Cartridge::Loader.from_file(requirement.path_of(Nestest::ROM_PATH))
    official_lines = Nestest::Log.official_lines(File.read(requirement.path_of(Nestest::LOG_PATH)))
    runner = Nestest::Runner.automation_mode(cartridge)

    divergence = runner.first_divergence(official_lines)
    abort divergence.message if divergence

    official_line_count = official_lines.size
    official_result_code = runner.official_result
    success_message = format(
      'All %<official_line_count>d official lines match; $0002 = $%<official_result_code>02X',
      official_line_count:,
      official_result_code:
    )
    puts success_message
  end
end
