# frozen_string_literal: true

module CpuBenchmark
  # The JIT configurations the benchmark measures, each with the `ruby` flags that select it. A Ruby built without
  # one of the JITs has no `RubyVM::YJIT` or `RubyVM::ZJIT` constant, so the current configuration reads them only
  # when they are defined: the specs run on such a Ruby, the benchmark itself needs both (plan 10, decision 13).
  # Another engine is named after itself: a binary Spinel compiled from spinel/ (plan 26) reports 'spinel', and has
  # neither constant.
  module Configuration
    FLAGS = { 'interpreter' => [], 'yjit' => ['--yjit'], 'zjit' => ['--zjit'] }.freeze
    CRUBY = 'ruby'

    def self.current(yjit_enabled: defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?,
                     zjit_enabled: defined?(RubyVM::ZJIT) && RubyVM::ZJIT.enabled?,
                     engine: RUBY_ENGINE)
      if engine != CRUBY
        engine
      elsif zjit_enabled
        'zjit'
      elsif yjit_enabled
        'yjit'
      else
        'interpreter'
      end
    end
  end
end
