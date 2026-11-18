# frozen_string_literal: true

require 'net/http'
require 'openssl'
require 'zlib'

module TestRoms
  # A source could not deliver a file: unreachable, too slow, or it answered with something other than the file.
  class DownloadError < StandardError; end

  # Downloads one file over the network. Every failure is a DownloadError, so the caller can move on to the next
  # source without knowing how the network failed.
  class Downloader
    SUCCESS_STATUS = '200'
    TIMEOUTS = { open_timeout: 10, read_timeout: 30 }.freeze
    TRANSFER_FAILURES = [
      SocketError,
      SystemCallError,
      IOError,
      Timeout::Error,
      OpenSSL::SSL::SSLError,
      Net::ProtocolError,
      Net::HTTPBadResponse,
      Net::HTTPHeaderSyntaxError,
      Zlib::Error
    ].freeze

    def get(url)
      response = request(url)
      raise DownloadError, "#{url} answered #{response.code}" unless response.code == SUCCESS_STATUS

      response.body
    end

    private

    def request(url)
      parsed_url = URI(url)
      use_ssl = parsed_url.is_a?(URI::HTTPS)
      request_path = parsed_url.request_uri

      Net::HTTP
        .start(parsed_url.host, parsed_url.port, use_ssl:, **TIMEOUTS) { |connection| connection.get(request_path) }
    rescue *TRANSFER_FAILURES => error
      raise DownloadError, "#{url} could not be downloaded: #{error.message}"
    end
  end
end
