# frozen_string_literal: true

namespace :bench do
  # Each configuration and variant runs in a `ruby bench/cpu.rb` process of its own (plan 10, decision 3), and the
  # JSON lines they print become a dated section of docs/benchmarks.md. The variants run right after their
  # configuration's baseline, so a session's drift (the machine's thermal and turbo state) separates them by minutes
  # at most. The tasks load the benchmark when they run, not when rake starts: other tasks (build, rubocop) must not
  # depend on the emulator loading.
  append_report = ->(report_class, title:, measurements:) do
    brand = `sysctl -n machdep.cpu.brand_string 2>/dev/null`.strip
    machine = brand.empty? ? RbConfig::CONFIG['host'] : brand
    report = report_class.new(title:, date: Date.today, ruby: RUBY_DESCRIPTION, machine:, measurements:)
    markdown = report.to_markdown
    File.write(File.expand_path('../docs/benchmarks.md', __dir__), "\n#{markdown}", mode: 'a')
    puts markdown
  end

  # The frames `rake bench:profile` samples after the warm-up, unless given.
  profiled_frames = 200

  measure = ->(title:, variants:) do
    require 'date'
    require 'json'
    require 'open3'

    script = File.expand_path('../bench/cpu.rb', __dir__)
    configurations = CpuBenchmark::Configuration::FLAGS
    measurements = configurations.keys.product(variants).map do |configuration, variant|
      puts "#{configuration} / #{variant}…"
      output, status = Open3.capture2(RbConfig.ruby, *configurations.fetch(configuration), script, '--variant', variant)
      abort "bench/cpu.rb failed under #{configuration} with #{variant}" unless status.success?

      JSON.parse(output, symbolize_names: true)
    end

    append_report.call(CpuBenchmark::Report, title:, measurements:)
  end

  workload_description = -> do
    defaults = CpuBenchmark::Options::WORKLOAD_DEFAULTS
    format(
      'nestest, %<million_cycles>d M cycles, %<warm_up_runs>d warm-up and %<measured_runs>d measured runs',
      million_cycles: defaults[:cycles] / CpuBenchmark::Sample::CYCLES_PER_MEGAHERTZ,
      warm_up_runs: defaults[:warm_up_runs],
      measured_runs: defaults[:measured_runs]
    )
  end

  desc 'Measure the CPU on nestest under no JIT, YJIT and ZJIT; append the table to docs/benchmarks.md'
  task :cpu do
    require_relative '../bench/cpu_benchmark'

    measure.call(title: "CPU baseline (#{workload_description.call})", variants: [CpuBenchmark::Variants::BASELINE])
  end

  desc 'Measure every hot-path variant under no JIT, YJIT and ZJIT; append the table to docs/benchmarks.md'
  task :variants do
    require_relative '../bench/cpu_benchmark'

    measure.call(title: "CPU variants (#{workload_description.call})", variants: CpuBenchmark::Variants::NAMES)
  end

  desc(
    'Play Super Mario Bros. 3 into world 1-1 under no JIT, YJIT and ZJIT (plan 25); append the table to ' \
    'docs/benchmarks.md'
  )
  task :frames, [:title] do |_task, arguments|
    require 'date'
    require 'json'
    require 'open3'
    require_relative '../bench/frame_benchmark'

    # Without the local ROM, bench/frame.rb says where to put it and fails, which stops the task.
    options = FrameBenchmark::Options.parse([])
    script = File.expand_path('../bench/frame.rb', __dir__)
    measurements = CpuBenchmark::Configuration::FLAGS.map do |configuration, flags|
      puts "#{configuration}…"
      output, status = Open3.capture2(RbConfig.ruby, *flags, script)
      abort "bench/frame.rb failed under #{configuration}" unless status.success?

      JSON.parse(output, symbolize_names: true)
    end

    workload = format(
      'Super Mario Bros. 3, world 1-1 with audio, %<warm_up>d warm-up frames and %<runs>d runs of %<frames>d',
      warm_up: options.warm_up_frames,
      runs: options.measured_runs,
      frames: options.frames_per_run
    )
    title = [arguments[:title] || 'Frames', workload].join(' — ')
    append_report.call(FrameBenchmark::Report, title:, measurements:)
  end

  desc(
    'Profile Super Mario Bros. 3 in world 1-1 with vernier under YJIT (plan 25); print the top methods and keep the ' \
    'whole profile in tmp/'
  )
  task :profile, [:frames] do |_task, arguments|
    require 'vernier'
    require_relative '../bench/frame_benchmark'

    options = FrameBenchmark::Options.parse([])
    abort format(FrameBenchmark::CommandLine::MISSING_ROM, path: options.rom) unless File.exist?(options.rom)

    RubyVM::YJIT.enable
    workload = FrameBenchmark::Workload.from_files(rom: options.rom, input: options.input)
    workload.run(frames: options.warm_up_frames)
    frames = Integer(arguments[:frames] || profiled_frames)
    path = File.expand_path('../tmp/frame-profile.json', __dir__)
    FileUtils.mkdir_p(File.dirname(path))
    result = Vernier.profile(out: path) { workload.run(frames:) }
    puts Vernier::Output::Top.new(result, 40).output, "The whole profile (Firefox Profiler format): #{path}"
  end

  desc 'Run nestest in each windowed backend under no JIT, YJIT and ZJIT (plan 17); print the table'
  task :frontends, [:frames] do |_task, arguments|
    require 'json'
    require 'open3'
    require_relative '../bench/frontend_benchmark'
    require_relative '../spec/support/test_roms'
    require_relative '../spec/support/nestest'

    requirement = TestRoms.requirement
    unavailable_reason = requirement.skip_reason([Nestest::ROM_PATH])
    abort unavailable_reason if unavailable_reason

    script = File.expand_path('../bench/frontends.rb', __dir__)
    frames = arguments[:frames] || FrontendBenchmark::Options::MEASURED_FRAMES.to_s
    rows = FrontendBenchmark::Backends::NAMES.product(CpuBenchmark::Configuration::FLAGS.keys).map do |backend, jit|
      puts "#{backend} / #{jit}…"
      command = [
        RbConfig.ruby,
        *CpuBenchmark::Configuration::FLAGS.fetch(jit),
        script,
        requirement.path_of(Nestest::ROM_PATH),
        '--backend',
        backend,
        '--frames',
        frames
      ]
      output, status = Open3.capture2(*command)
      abort "bench/frontends.rb failed with #{backend} under #{jit}" unless status.success?

      # raylib writes its warnings to standard output too; the measurement is the last line.
      measurement = JSON.parse(output.lines.last, symbolize_names: true)
      format(
        '| %<backend>s | %<jit>s | %<present>.2f | %<frame>.2f | %<rate>.1f |',
        backend:,
        jit:,
        present: measurement[:present_milliseconds],
        frame: measurement[:frame_milliseconds],
        rate: measurement[:frames_per_second]
      )
    end

    puts "\n#{RUBY_DESCRIPTION}, nestest, #{frames} frames, medians", ''
    puts '| Backend | JIT | Present (ms) | Frame (ms) | Frames per second |', '|---|---|---|---|---|', rows
  end
end
