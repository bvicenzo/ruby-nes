# frozen_string_literal: true

require 'digest'

module TestRoms
  # One file of the test ROM manifest: its path inside the collection and the SHA-256 checksum (lowercase hex) of the
  # content we expect.
  Entry = Data.define(:path, :checksum) do
    def local_path(directory) = File.join(directory, path)

    def matching?(content) = Digest::SHA256.hexdigest(content) == checksum

    def intact_in?(directory)
      local_file_path = local_path(directory)

      File.file?(local_file_path) && matching?(File.binread(local_file_path))
    end
  end
end
