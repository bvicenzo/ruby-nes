# frozen_string_literal: true

module FrontendBenchmark
  # The windowed backends, by the name bench/frontends.rb takes: raylib, the one plan 17 chose (SDL3, the other one it
  # compared, was removed; docs/backend-comparison.md). Each is loaded only when asked for: its gem is in the optional
  # `frontends` Gemfile group.
  module Backends
    FRONTENDS_DIRECTORY = File.expand_path('../../lib/ruby/nes/frontends', __dir__)
    CLASS_NAMES = { 'raylib' => :Raylib }.freeze
    NAMES = CLASS_NAMES.keys.freeze

    # The frontend class of a backend named in NAMES, after loading its file (and its gem).
    def self.load(name)
      require File.join(FRONTENDS_DIRECTORY, name)
      Ruby::Nes::Frontends.const_get(CLASS_NAMES.fetch(name))
    end
  end
end
