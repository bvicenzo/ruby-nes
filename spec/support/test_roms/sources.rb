# frozen_string_literal: true

module TestRoms
  # No source delivered a file with the checksum the manifest expects.
  class FetchError < StandardError; end

  # The sources of the manifest, tried in order for a file. Any source serving bytes with the expected checksum is as
  # good as the upstream collection, so the first one that does wins.
  class Sources
    def initialize(manifest:, downloader:)
      @manifest = manifest
      @downloader = downloader
    end

    def content_for(entry)
      failures = @manifest.urls_for(entry).map do |url|
        content = @downloader.get(url)
        return content if entry.matching?(content)

        "#{url} delivered content that does not match the checksum"
      rescue DownloadError => error
        error.message
      end

      raise FetchError, "No source delivered #{entry.path}:\n  #{failures.join("\n  ")}"
    end
  end
end
