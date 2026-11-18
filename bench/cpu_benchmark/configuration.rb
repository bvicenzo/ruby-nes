# frozen_string_literal: true

module CpuBenchmark
  # The JIT configurations the benchmark measures, each with the `ruby` flags that select it. A Ruby built without
  # one of the JITs has no `RubyVM::YJIT` or `RubyVM::ZJIT` constant, so the current configuration reads them only
  # when they are defined: the specs run on such a Ruby, the benchmark itself needs both (plan 10, decision 13).
  module Configuration
    FLAGS = { 'interpreter' => [], 'yjit' => ['--yjit'], 'zjit' => ['--zjit'] }.freeze

    def self.current(yjit_enabled: defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?,
                     zjit_enabled: defined?(RubyVM::ZJIT) && RubyVM::ZJIT.enabled?)
      if zjit_enabled
        'zjit'
      elsif yjit_enabled
        'yjit'
      else
        'interpreter'
      end
    end
  end
end
