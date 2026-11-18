# frozen_string_literal: true

module Nestest
  # The first line where the tracer and nestest.log disagree: its number in the compared lines (the log's own line
  # number, since the official section starts at the log's first line), the log's line and the tracer's, both in the
  # tracer's layout.
  Divergence = Data.define(:line_number, :expected, :actual) do
    def message
      <<~MESSAGE
        nestest.log line #{line_number} differs:
          expected: #{expected}
          actual:   #{actual}
      MESSAGE
    end
  end
end
