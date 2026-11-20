# frozen_string_literal: true

module Ruby
  module Nes
    module Frontends
      # Where the raylib-bindings gem keeps the raylib library of its platform build (plan 17): in its lib/ directory,
      # named by processor on macOS and Linux (libraylib.x86_64.dylib, libraylib.aarch64.so) and libraylib.dll on
      # Windows (the gem's x64-mingw build), as the gem's files show for 0.8.4. Kept apart from Frontends::Raylib so
      # it needs no gem to load.
      module RaylibLibrary
        WINDOWS_FILE = 'libraylib.dll'
        # The operating system as RbConfig's host_os names it, to the library's file extension.
        EXTENSIONS = { /darwin/ => 'dylib', /linux/ => 'so' }.freeze
        WINDOWS = /mingw|mswin/

        def self.path(gem_directory:, host_os:, host_cpu:)
          File.join(gem_directory, 'lib', file_name(host_os, host_cpu))
        end

        def self.file_name(host_os, host_cpu)
          return WINDOWS_FILE if host_os.match?(WINDOWS)

          extension = EXTENSIONS.find { |system, _extension| host_os.match?(system) }&.last
          raise LoadError, "raylib-bindings ships no raylib library for #{host_os}" unless extension

          "libraylib.#{host_cpu}.#{extension}"
        end

        private_class_method :file_name
      end
    end
  end
end
