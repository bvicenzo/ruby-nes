# frozen_string_literal: true

RSpec.describe Ruby::Nes::Cartridge::Header do
  describe '.parse' do
    context 'when the image is shorter than a header' do
      let(:image) { HexDump.bytes('4E 45 53 1A 02 01 00 00 00 00 00 00 00 00 00') }

      it 'raises InvalidImage naming the length' do
        expect { described_class.parse(image) }
          .to raise_error(Ruby::Nes::Cartridge::InvalidImage, /15 bytes/)
      end
    end

    context 'when the image holds a whole header' do
      context 'but it does not start with the iNES magic' do
        let(:image) { HexDump.bytes('4E 45 53 00 02 01 00 00 00 00 00 00 00 00 00 00') }

        it 'raises InvalidImage naming the magic' do
          expect { described_class.parse(image) }
            .to raise_error(Ruby::Nes::Cartridge::InvalidImage, /iNES magic/)
        end
      end

      context 'and it starts with the iNES magic' do
        let(:expected_header) do
          described_class.new(
            prg_rom_size: 32_768,
            chr_rom_size: 8_192,
            mirroring: :horizontal,
            battery: false,
            trainer: false,
            alternative_nametables: false,
            nes2: false,
            mapper_number: 0x14
          )
        end

        context 'and bytes 8 to 11 are zero' do
          let(:image) { HexDump.bytes('4E 45 53 1A 02 01 40 10 00 00 00 00 00 00 00 00') }

          it 'returns a header' do
            expect(described_class.parse(image)).to eq(expected_header)
          end
        end

        context 'and bytes 8 to 11 are not zero' do
          let(:image) { HexDump.bytes('4E 45 53 1A 02 01 40 10 FF FF FF FF 00 00 00 00') }

          it 'returns the same header as when they are zero' do
            expect(described_class.parse(image)).to eq(expected_header)
          end
        end
      end
    end

    context 'when the image is longer than a header' do
      let(:image) { HexDump.bytes('4E 45 53 1A 02 01 00 00 00 00 00 00 00 00 00 00 FF FF') }

      it 'decodes only the first sixteen bytes' do
        expect(described_class.parse(image)).to have_attributes(prg_rom_size: 32_768, chr_rom_size: 8_192)
      end
    end
  end

  describe '#prg_rom_size' do
    subject(:header) { described_class.parse(image) }

    context 'when byte 4 counts two units' do
      let(:image) { HexDump.bytes('4E 45 53 1A 02 00 00 00 00 00 00 00 00 00 00 00') }

      it 'is 32 KiB' do
        expect(header.prg_rom_size).to eq(32_768)
      end
    end
  end

  describe '#chr_rom_size' do
    subject(:header) { described_class.parse(image) }

    context 'when byte 5 counts two units' do
      let(:image) { HexDump.bytes('4E 45 53 1A 01 02 00 00 00 00 00 00 00 00 00 00') }

      it 'is 16 KiB' do
        expect(header.chr_rom_size).to eq(16_384)
      end
    end
  end

  describe '#chr_ram?' do
    subject(:header) { described_class.parse(image) }

    context 'when byte 5 is zero' do
      let(:image) { HexDump.bytes('4E 45 53 1A 01 00 00 00 00 00 00 00 00 00 00 00') }

      it { is_expected.to be_chr_ram }
    end

    context 'when byte 5 counts units' do
      let(:image) { HexDump.bytes('4E 45 53 1A 01 01 00 00 00 00 00 00 00 00 00 00') }

      it { is_expected.not_to be_chr_ram }
    end
  end

  describe '#chr_ram_size' do
    subject(:header) { described_class.parse(image) }

    context 'when byte 5 is zero' do
      let(:image) { HexDump.bytes('4E 45 53 1A 01 00 00 00 00 00 00 00 00 00 00 00') }

      it 'is 8 KiB' do
        expect(header.chr_ram_size).to eq(8_192)
      end
    end

    context 'when byte 5 counts units' do
      let(:image) { HexDump.bytes('4E 45 53 1A 01 01 00 00 00 00 00 00 00 00 00 00') }

      it 'is zero' do
        expect(header.chr_ram_size).to eq(0)
      end
    end
  end

  describe '#mirroring' do
    subject(:header) { described_class.parse(image) }

    context 'when byte 6 bit 0 is clear' do
      let(:image) { HexDump.bytes('4E 45 53 1A 01 01 00 00 00 00 00 00 00 00 00 00') }

      it 'is horizontal' do
        expect(header.mirroring).to eq(:horizontal)
      end
    end

    context 'when byte 6 bit 0 is set' do
      let(:image) { HexDump.bytes('4E 45 53 1A 01 01 01 00 00 00 00 00 00 00 00 00') }

      it 'is vertical' do
        expect(header.mirroring).to eq(:vertical)
      end
    end
  end

  describe '#battery?' do
    subject(:header) { described_class.parse(image) }

    context 'when byte 6 bit 1 is clear' do
      let(:image) { HexDump.bytes('4E 45 53 1A 01 01 00 00 00 00 00 00 00 00 00 00') }

      it { is_expected.not_to be_battery }
    end

    context 'when byte 6 bit 1 is set' do
      let(:image) { HexDump.bytes('4E 45 53 1A 01 01 02 00 00 00 00 00 00 00 00 00') }

      it { is_expected.to be_battery }
    end
  end

  describe '#trainer?' do
    subject(:header) { described_class.parse(image) }

    context 'when byte 6 bit 2 is clear' do
      let(:image) { HexDump.bytes('4E 45 53 1A 01 01 00 00 00 00 00 00 00 00 00 00') }

      it { is_expected.not_to be_trainer }
    end

    context 'when byte 6 bit 2 is set' do
      let(:image) { HexDump.bytes('4E 45 53 1A 01 01 04 00 00 00 00 00 00 00 00 00') }

      it { is_expected.to be_trainer }
    end
  end

  describe '#trainer_size' do
    subject(:header) { described_class.parse(image) }

    context 'when byte 6 bit 2 is clear' do
      let(:image) { HexDump.bytes('4E 45 53 1A 01 01 00 00 00 00 00 00 00 00 00 00') }

      it 'is zero' do
        expect(header.trainer_size).to eq(0)
      end
    end

    context 'when byte 6 bit 2 is set' do
      let(:image) { HexDump.bytes('4E 45 53 1A 01 01 04 00 00 00 00 00 00 00 00 00') }

      it 'is 512 bytes' do
        expect(header.trainer_size).to eq(512)
      end
    end
  end

  describe '#alternative_nametables?' do
    subject(:header) { described_class.parse(image) }

    context 'when byte 6 bit 3 is clear' do
      let(:image) { HexDump.bytes('4E 45 53 1A 01 01 00 00 00 00 00 00 00 00 00 00') }

      it { is_expected.not_to be_alternative_nametables }
    end

    context 'when byte 6 bit 3 is set' do
      let(:image) { HexDump.bytes('4E 45 53 1A 01 01 08 00 00 00 00 00 00 00 00 00') }

      it { is_expected.to be_alternative_nametables }
    end
  end

  describe '#nes2?' do
    subject(:header) { described_class.parse(image) }

    context 'when byte 7 bit 3 is clear' do
      let(:image) { HexDump.bytes('4E 45 53 1A 01 01 00 04 00 00 00 00 00 00 00 00') }

      it { is_expected.not_to be_nes2 }
    end

    context 'when byte 7 bit 3 is set' do
      context 'but bit 2 is also set' do
        let(:image) { HexDump.bytes('4E 45 53 1A 01 01 00 0C 00 00 00 00 00 00 00 00') }

        it { is_expected.not_to be_nes2 }
      end

      context 'and bit 2 is clear' do
        let(:image) { HexDump.bytes('4E 45 53 1A 01 01 00 08 00 00 00 00 00 00 00 00') }

        it { is_expected.to be_nes2 }
      end
    end
  end

  describe '#mapper_number' do
    subject(:header) { described_class.parse(image) }

    context 'when byte 7 bits 2 and 3 mark an archaic header' do
      let(:image) { HexDump.bytes('4E 45 53 1A 01 01 40 14 00 00 00 00 00 00 00 00') }

      it 'keeps only the byte 6 nibble' do
        expect(header.mapper_number).to eq(0x04)
      end
    end

    context 'when byte 7 bits 2 and 3 do not mark an archaic header' do
      context 'and bytes 12 to 15 are zero' do
        context 'and byte 7 has nothing besides its nibble' do
          let(:image) { HexDump.bytes('4E 45 53 1A 01 01 40 10 00 00 00 00 00 00 00 00') }

          it 'combines the byte 6 nibble as the low half with the byte 7 nibble as the high half' do
            expect(header.mapper_number).to eq(0x14)
          end
        end

        context 'and byte 11 is not zero' do
          let(:image) { HexDump.bytes('4E 45 53 1A 01 01 40 10 00 00 00 FF 00 00 00 00') }

          it 'combines both nibbles' do
            expect(header.mapper_number).to eq(0x14)
          end
        end

        context 'and byte 7 flags VS Unisystem and PlayChoice-10' do
          let(:image) { HexDump.bytes('4E 45 53 1A 01 01 40 13 00 00 00 00 00 00 00 00') }

          it 'combines both nibbles' do
            expect(header.mapper_number).to eq(0x14)
          end
        end
      end

      context 'and one of bytes 12 to 15 is not zero' do
        context 'but the header is NES 2.0' do
          let(:image) { HexDump.bytes('4E 45 53 1A 01 01 40 18 00 00 00 00 00 00 00 01') }

          it 'combines both nibbles' do
            expect(header.mapper_number).to eq(0x14)
          end
        end

        context 'and the header is not NES 2.0' do
          context 'and the non-zero byte is 12' do
            let(:image) { HexDump.bytes('4E 45 53 1A 01 01 40 10 00 00 00 00 44 00 00 00') }

            it 'keeps only the byte 6 nibble' do
              expect(header.mapper_number).to eq(0x04)
            end
          end

          context 'and the non-zero byte is 15' do
            let(:image) { HexDump.bytes('4E 45 53 1A 01 01 40 10 00 00 00 00 00 00 00 21') }

            it 'keeps only the byte 6 nibble' do
              expect(header.mapper_number).to eq(0x04)
            end
          end
        end
      end
    end
  end
end
