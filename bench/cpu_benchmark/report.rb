# frozen_string_literal: true

module CpuBenchmark
  # A dated section of docs/benchmarks.md: the Ruby and the machine measured, then one row per configuration and
  # variant, each variant compared with the baseline measured under the same configuration in the same session.
  class Report
    TABLE_HEADER = <<~MARKDOWN
      | Configuration | Variant | Emulated MHz | % of real time | Spread | Change from baseline |
      |---|---|---|---|---|---|
    MARKDOWN
    ROW_FORMAT = '| %<configuration>s | %<variant>s | %<megahertz>.2f | %<percent_of_real_time>.0f%% ' \
                 "| %<spread>.1f%% | %<change>s |\n"
    NO_CHANGE = '—'

    # `measurements` are the JSON lines of bench/cpu.rb, with symbol keys.
    def initialize(title:, date:, ruby:, machine:, measurements:)
      @title = title
      @date = date
      @ruby = ruby
      @machine = machine
      @measurements = measurements
      @baselines = baselines_by_configuration(measurements)
    end

    def to_markdown
      heading = "### #{@date.iso8601} — #{@title}\n\n#{@ruby}; #{@machine}\n\n"
      rows = @measurements.map { |measurement| row(measurement) }.join
      heading + TABLE_HEADER + rows
    end

    private

    def row(measurement)
      format(ROW_FORMAT, **measurement, change: change_from_baseline(measurement))
    end

    def change_from_baseline(measurement)
      return NO_CHANGE if measurement[:variant] == Variants::BASELINE

      baseline = @baselines.fetch(measurement[:configuration])
      format('%+.1f%%', ((measurement[:megahertz] / baseline[:megahertz]) - 1) * Summary::PERCENT)
    end

    def baselines_by_configuration(measurements)
      measurements
        .select { |measurement| measurement[:variant] == Variants::BASELINE }
        .to_h { |measurement| [measurement[:configuration], measurement] }
    end
  end
end
