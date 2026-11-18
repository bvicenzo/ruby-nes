# frozen_string_literal: true

module CpuBenchmark
  # The variant asked for is not a file of bench/cpu_benchmark/variants.
  class UnknownVariant < Error; end

  # The hot-path experiments of plan 10. Each is a file that reopens core classes, so it is loaded only inside a
  # benchmark process of its own (plan 10, decision 3), never by the specs or the emulator. `baseline` reopens
  # nothing: it is the reference the others are compared with.
  module Variants
    BASELINE = 'baseline'
    NAMES = %w[
      baseline
      dispatch_lambda_table
      memory_string
      memory_io_buffer
      bits_helpers
      interrupt_poll_inline
    ].freeze
    DIRECTORY = File.expand_path('variants', __dir__)

    def self.path(name)
      raise UnknownVariant, "#{name} is not a variant; the variants are #{NAMES.join(', ')}" unless NAMES.include?(name)

      File.join(DIRECTORY, "#{name}.rb")
    end
  end
end
