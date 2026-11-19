# frozen_string_literal: true

namespace :blargg do
  desc 'Run a blargg test ROM of the manifest and print its result: rake blargg:run[<path>,<frame limit>]'
  task :run, [:rom, :frame_limit] do |_task, arguments|
    # Loaded here, not at the top: other rake tasks (build, rubocop) must not depend on the emulator loading.
    require_relative '../lib/ruby/nes'
    require_relative '../spec/support/hex_dump'
    require_relative '../spec/support/test_roms'
    require_relative '../spec/support/blargg'

    rom = arguments[:rom] or abort 'Give the ROM path of the manifest: rake blargg:run[<path>]'
    requirement = TestRoms.requirement
    unavailable_reason = requirement.skip_reason([rom])
    abort unavailable_reason if unavailable_reason

    console = Ruby::Nes::Console.new(Ruby::Nes::Cartridge::Loader.from_file(requirement.path_of(rom)))
    frame_limit = Integer(arguments[:frame_limit] || Blargg::Runner::FRAME_LIMIT)
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    outcome = Blargg::Runner.new(console, frame_limit:).run
    seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at

    summary = format(
      '%<rom>s: %<state>s, code $%<code>02X, %<frames>d frames in %<seconds>.1f s',
      rom:,
      state: outcome.state,
      code: outcome.code,
      frames: outcome.frames,
      seconds:
    )
    puts summary, outcome.text
  end
end
