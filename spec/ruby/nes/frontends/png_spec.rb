# frozen_string_literal: true

require 'zlib'
require 'ruby/nes/frontends/png'

# PNG (https://www.w3.org/TR/png-3/): the 8-byte signature "137 80 78 71 13 10 26 10", then chunks, each a 4-byte
# length, a 4-byte type, the data and "A four-byte CRC calculated on the preceding bytes in the chunk, including the
# chunk type field and chunk data fields, but not including the length field", all integers "in network byte order"
# (big-endian). IHDR comes first: width, height, bit depth, colour type (2, Truecolour: red, green and blue samples),
# compression method 0, filter method 0 and interlace method 0 (none). IDAT holds the zlib datastream of the
# scanlines, each "preceded by a filter-type byte" (0, None). IEND is empty and last.
RSpec.describe Ruby::Nes::Frontends::Png do
  describe '.encode' do
    context 'when the RGB bytes do not fill width × height pixels' do
      let(:rgb) { "\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0A\x0B".b }

      it 'raises an argument error' do
        expect { described_class.encode(width: 2, height: 2, rgb:) }.to raise_error(ArgumentError, /12 bytes/)
      end
    end

    context 'when they fill them' do
      let(:rgb) { "\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0A\x0B\x0C".b }
      let(:png) { described_class.encode(width: 2, height: 2, rgb:) }
      # After the signature: IHDR (4 + 4 + 13 + 4 bytes), then IDAT, whose length is its first 4 bytes, then IEND.
      let(:image_chunk_length) { png.byteslice(33, 4).unpack1('N') }
      let(:compressed_image) { png.byteslice(41, image_chunk_length) }

      it 'starts with the PNG signature' do
        expect(png.byteslice(0, 8)).to eq([137, 80, 78, 71, 13, 10, 26, 10].pack('C*'))
      end

      it 'describes the image in its IHDR chunk' do
        expect(png.byteslice(8, 21).unpack('Na4NNC5')).to eq([13, 'IHDR', 2, 2, 8, 2, 0, 0, 0])
      end

      it 'stores each row after filter type 0 in its IDAT chunk', :aggregate_failures do
        expect(png.byteslice(37, 4)).to eq('IDAT')
        filtered_rows = "\x00\x01\x02\x03\x04\x05\x06\x00\x07\x08\x09\x0A\x0B\x0C".b
        expect(Zlib::Inflate.inflate(compressed_image)).to eq(filtered_rows)
      end

      it 'ends with an empty IEND chunk' do
        expect(png.byteslice(-12, 8).unpack('Na4')).to eq([0, 'IEND'])
      end

      it 'closes every chunk with the CRC of its type and data', :aggregate_failures do
        expect(png.byteslice(29, 4).unpack1('N')).to eq(Zlib.crc32(png.byteslice(12, 17)))
        expect(png.byteslice(41 + image_chunk_length, 4).unpack1('N')).to eq(Zlib.crc32("IDAT#{compressed_image}"))
        expect(png.byteslice(-4, 4).unpack1('N')).to eq(Zlib.crc32('IEND'))
      end
    end
  end
end
