# frozen_string_literal: true

require 'zlib'

module Ruby
  module Nes
    module Frontends
      # A minimal PNG encoder (https://www.w3.org/TR/png-3/) for the headless frontend's screenshots: one truecolour
      # image, 8 bits per sample, no interlace, every scanline with filter type 0 (None), compressed with zlib. Off the
      # hot path.
      #
      # The file is the signature, then the IHDR, IDAT and IEND chunks. A chunk is its data's length, its type, the
      # data and "A four-byte CRC calculated on the preceding bytes in the chunk, including the chunk type field and
      # chunk data fields, but not including the length field"; integers are "in network byte order" (big-endian).
      module Png
        SIGNATURE = [137, 80, 78, 71, 13, 10, 26, 10].pack('C*').freeze
        BIT_DEPTH = 8
        # Truecolour: "Each pixel is an R,G,B triple".
        TRUECOLOUR = 2
        COMPRESSION_METHOD = 0
        FILTER_METHOD = 0
        NO_INTERLACE = 0
        # Each scanline is "preceded by a filter-type byte"; type 0 leaves the bytes as they are.
        NO_FILTER = "\x00".b.freeze
        BYTES_PER_PIXEL = 3

        # The PNG file of an image given as its red, green and blue bytes, row by row; RGB bytes that do not fill
        # width × height pixels raise ArgumentError.
        def self.encode(width:, height:, rgb:)
          row_size = width * BYTES_PER_PIXEL
          expected_size = row_size * height
          unless rgb.bytesize == expected_size
            message = "#{width}×#{height} pixels need #{expected_size} bytes, got #{rgb.bytesize}"
            raise ArgumentError, message
          end

          header_chunk = chunk('IHDR', header(width, height))
          SIGNATURE + header_chunk + chunk('IDAT', image_data(rgb, row_size)) + chunk('IEND', '')
        end

        def self.header(width, height)
          [width, height, BIT_DEPTH, TRUECOLOUR, COMPRESSION_METHOD, FILTER_METHOD, NO_INTERLACE].pack('NNC5')
        end

        def self.image_data(rgb, row_size)
          scanlines = (0...rgb.bytesize).step(row_size).map { NO_FILTER + rgb.byteslice(it, row_size) }.join
          Zlib::Deflate.deflate(scanlines)
        end

        def self.chunk(type, data)
          [data.bytesize].pack('N') + type + data + [Zlib.crc32(type + data)].pack('N')
        end

        private_class_method :header, :image_data, :chunk
      end
    end
  end
end
