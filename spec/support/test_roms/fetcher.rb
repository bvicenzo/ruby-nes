# frozen_string_literal: true

require 'fileutils'

module TestRoms
  # Makes every manifest file present and intact in a local directory, yielding each file's path and outcome
  # (:up_to_date or :downloaded) as soon as it is settled; the block is required. Intact files are left alone; missing
  # or corrupted ones are downloaded again. A download is written beside the file and renamed into place, so a failed or
  # interrupted one never replaces a file. The first file no source delivers stops the fetch.
  class Fetcher
    PARTIAL_DOWNLOAD_SUFFIX = '.download'

    def initialize(entries:, directory:, sources:)
      @entries = entries
      @directory = directory
      @sources = sources
    end

    def fetch
      @entries.each do |entry|
        outcome = fetch_entry(entry)
        yield entry.path, outcome
      end
    end

    private

    def fetch_entry(entry)
      return :up_to_date if entry.intact_in?(@directory)

      write(entry.local_path(@directory), @sources.content_for(entry))
      :downloaded
    end

    def write(file_path, content)
      partial_file_path = "#{file_path}#{PARTIAL_DOWNLOAD_SUFFIX}"

      FileUtils.mkdir_p(File.dirname(file_path))
      File.binwrite(partial_file_path, content)
      File.rename(partial_file_path, file_path)
    ensure
      FileUtils.rm_f(partial_file_path)
    end
  end
end
