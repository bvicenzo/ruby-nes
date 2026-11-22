# frozen_string_literal: true

module FrameBenchmark
  # A dated section of docs/benchmarks.md: one row per configuration, the digests shortened. A JIT never changes the
  # output, so digests that differ between configurations are called out.
  class Report
    TABLE_HEADER = <<~MARKDOWN
      | Configuration | Frames per second | ms per frame | % of real time | Spread | Frame digest | Audio digest |
      |---|---|---|---|---|---|---|
    MARKDOWN
    ROW_FORMAT = '| %<configuration>s | %<frames_per_second>.1f | %<milliseconds_per_frame>.1f ' \
                 '| %<percent_of_real_time>.0f%% | %<spread>.1f%% | %<frame>s | %<audio>s |' \
                 "\n"
    DIGEST_LENGTH = 12
    DIGESTS_DIFFER = "\nThe digests differ between configurations.\n"

    def initialize(title:, date:, ruby:, machine:, measurements:)
      @title = title
      @date = date
      @ruby = ruby
      @machine = machine
      @measurements = measurements
    end

    def to_markdown
      heading = "### #{@date.iso8601} — #{@title}\n\n#{@ruby}; #{@machine}\n\n"
      rows = @measurements.map { |measurement| row(measurement) }.join
      heading + TABLE_HEADER + rows + digests_note
    end

    private

    def row(measurement)
      format(
        ROW_FORMAT,
        **measurement,
        frame: measurement[:frame_digest][0, DIGEST_LENGTH],
        audio: measurement[:audio_digest][0, DIGEST_LENGTH]
      )
    end

    def digests_note
      digests = @measurements.map { |measurement| measurement.values_at(:frame_digest, :audio_digest) }
      digests.uniq.size > 1 ? DIGESTS_DIFFER : ''
    end
  end
end
