# frozen_string_literal: true

module TestRoms
  # What a spec needs from the local test ROM directory. A path the manifest does not list raises: a typo must never
  # turn into a skipped spec.
  class Requirement
    FETCH_COMMAND = 'bundle exec rake test_roms:fetch'
    # A bare `:test_rom` tag declares `true`, which names no ROM.
    PATHS_EXPECTED = "declare the ROM paths: test_rom: 'path' or test_rom: ['path', ...]"

    def initialize(manifest:, directory:)
      @manifest = manifest
      @directory = directory
    end

    def skip_reason(paths)
      unavailable_paths = paths
        .map { |path| @manifest.find(path) }
        .reject { |entry| entry.intact_in?(@directory) }
        .map(&:path)
      return if unavailable_paths.empty?

      "Test ROMs missing or corrupted (#{unavailable_paths.join(', ')}): run `#{FETCH_COMMAND}`"
    end

    def ensure_listed(paths)
      raise UnknownRomError, PATHS_EXPECTED unless paths.all?(String)

      paths.each { |path| @manifest.find(path) }
    end

    def path_of(path) = @manifest.find(path).local_path(@directory)
  end
end
