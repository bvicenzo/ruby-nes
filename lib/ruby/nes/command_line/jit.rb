# frozen_string_literal: true

module Ruby
  module Nes
    class CommandLine
      # The JIT the emulator runs under (plan 18, decisions 1 and 8), enabled at runtime: on Ruby 4.0.9 both
      # `RubyVM::YJIT.enable` and `RubyVM::ZJIT.enable` work without a command-line flag. Ruby runs one JIT at a time
      # and cannot turn one off, so a JIT already running (from RUBYOPT or a flag) that differs from the one asked is
      # an error: the run never silently differs from what was asked. Off the hot path: once per run.
      class Jit
        # The JIT asked cannot be the one running: the message says why.
        class Unavailable < Error; end

        NONE = 'none'
        # The JITs of this Ruby, by the name `--jit` takes; a Ruby built without one has no entry for it.
        COMPILERS = { 'yjit' => :YJIT, 'zjit' => :ZJIT }
          .select { |_name, constant| RubyVM.const_defined?(constant) }
          .transform_values { RubyVM.const_get(it) }
          .freeze

        # `compilers` maps JIT names to objects answering `enabled?` and `enable`, as RubyVM::YJIT does.
        def initialize(compilers = COMPILERS)
          @compilers = compilers
        end

        # Enables the JIT named (`none` for none), unless it already runs; raises Unavailable when it cannot run.
        def enable(name)
          running_name = running
          return if running_name == name
          raise Unavailable, "#{running_name} is already running and cannot be turned off" if name == NONE

          compiler = @compilers.fetch(name) { raise Unavailable, "this Ruby has no #{name} (#{RUBY_DESCRIPTION})" }
          raise Unavailable, "#{running_name} is already running: Ruby cannot switch to #{name}" if running_name != NONE

          raise Unavailable, "#{name} could not be enabled" unless compiler.enable
        end

        # The name of the JIT running, or `none`.
        def running
          @compilers.find { |_name, compiler| compiler.enabled? }&.first || NONE
        end
      end
    end
  end
end
