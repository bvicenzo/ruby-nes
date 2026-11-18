# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'

RSpec.describe Ruby::Nes::Cartridge::Loader do
  describe '.from_bytes' do
    context 'when the image is not iNES' do
      let(:image) { HexDump.bytes('4E 45 53 00 01 01 00 00 00 00 00 00 00 00 00 00') }

      it 'raises InvalidImage' do
        expect { described_class.from_bytes(image) }.to raise_error(Ruby::Nes::Cartridge::InvalidImage)
      end
    end

    context 'when the image is iNES' do
      context 'but it holds fewer bytes than the header declares' do
        context 'and the header declares no trainer' do
          let(:image) do
            [
              HexDump.bytes('4E 45 53 1A 01 01 00 00 00 00 00 00 00 00 00 00'),
              HexDump.bytes('A0') * 16_384,
              HexDump.bytes('C0') * 8_191
            ].join
          end

          it 'raises TruncatedImage naming both sizes' do
            expect { described_class.from_bytes(image) }
              .to raise_error(Ruby::Nes::Cartridge::TruncatedImage, /24591 bytes.*declares 24592/)
          end
        end

        context 'and the header declares a trainer' do
          let(:image) do
            [
              HexDump.bytes('4E 45 53 1A 01 01 04 00 00 00 00 00 00 00 00 00'),
              HexDump.bytes('A0') * 16_384,
              HexDump.bytes('C0') * 8_192
            ].join
          end

          it 'raises TruncatedImage counting the trainer' do
            expect { described_class.from_bytes(image) }
              .to raise_error(Ruby::Nes::Cartridge::TruncatedImage, /24592 bytes.*declares 25104/)
          end
        end
      end

      context 'and it holds exactly the declared bytes' do
        context 'and the header declares no trainer' do
          context 'and the board has CHR ROM' do
            let(:image) do
              [
                HexDump.bytes('4E 45 53 1A 01 01 00 00 00 00 00 00 00 00 00 00'),
                HexDump.bytes('A0') * 16_384,
                HexDump.bytes('C0') * 8_192
              ].join
            end

            it 'returns the PRG ROM and the CHR ROM in order, with no trainer, frozen', :aggregate_failures do
              cartridge = described_class.from_bytes(image)

              expect(cartridge).to have_attributes(
                header: an_object_having_attributes(prg_rom_size: 16_384, chr_rom_size: 8_192),
                prg_rom: Array.new(16_384, 0xA0),
                chr_rom: Array.new(8_192, 0xC0),
                trainer: []
              )
              expect([cartridge.prg_rom, cartridge.chr_rom, cartridge.trainer]).to all(be_frozen)
            end
          end

          context 'and the board has CHR RAM' do
            let(:image) do
              [
                HexDump.bytes('4E 45 53 1A 01 00 00 00 00 00 00 00 00 00 00 00'),
                HexDump.bytes('A0') * 16_384
              ].join
            end

            it 'returns an empty CHR ROM' do
              expect(described_class.from_bytes(image))
                .to have_attributes(prg_rom: Array.new(16_384, 0xA0), chr_rom: [])
            end
          end
        end

        context 'and the header declares a trainer' do
          let(:image) do
            [
              HexDump.bytes('4E 45 53 1A 01 01 04 00 00 00 00 00 00 00 00 00'),
              HexDump.bytes('7E') * 512,
              HexDump.bytes('A0') * 16_384,
              HexDump.bytes('C0') * 8_192
            ].join
          end

          it 'reads the trainer after the header and the PRG ROM after the trainer' do
            expect(described_class.from_bytes(image)).to have_attributes(
              trainer: Array.new(512, 0x7E),
              prg_rom: Array.new(16_384, 0xA0),
              chr_rom: Array.new(8_192, 0xC0)
            )
          end
        end
      end

      context 'and it holds more than the declared bytes' do
        context 'and the board has CHR ROM' do
          let(:image) do
            [
              HexDump.bytes('4E 45 53 1A 01 01 00 00 00 00 00 00 00 00 00 00'),
              HexDump.bytes('A0') * 16_384,
              HexDump.bytes('C0') * 8_192,
              HexDump.bytes('FF') * 128
            ].join
          end

          it 'ends the CHR ROM at the declared size' do
            expect(described_class.from_bytes(image).chr_rom).to eq(Array.new(8_192, 0xC0))
          end
        end

        context 'and the board has CHR RAM' do
          let(:image) do
            [
              HexDump.bytes('4E 45 53 1A 01 00 00 00 00 00 00 00 00 00 00 00'),
              HexDump.bytes('A0') * 16_384,
              HexDump.bytes('FF') * 128
            ].join
          end

          it 'keeps the CHR ROM empty' do
            expect(described_class.from_bytes(image).chr_rom).to be_empty
          end
        end
      end
    end
  end

  describe '.from_file' do
    context 'when the file does not exist' do
      let(:directory) { Dir.mktmpdir }
      let(:rom_path) { File.join(directory, 'missing.nes') }

      after { FileUtils.remove_entry(directory) }

      it 'raises Errno::ENOENT' do
        expect { described_class.from_file(rom_path) }.to raise_error(Errno::ENOENT, /missing\.nes/)
      end
    end

    context 'when the file exists' do
      context 'and it is an image written by the spec' do
        let(:directory) { Dir.mktmpdir }
        let(:rom_path) { File.join(directory, 'game.nes') }
        let(:image) do
          [
            HexDump.bytes('4E 45 53 1A 01 01 01 00 00 00 00 00 00 00 00 00'),
            HexDump.bytes('A0') * 16_384,
            HexDump.bytes('C0') * 8_192
          ].join
        end

        before { File.binwrite(rom_path, image) }

        after { FileUtils.remove_entry(directory) }

        it 'reads it as binary into a cartridge' do
          expect(described_class.from_file(rom_path)).to have_attributes(
            header: an_object_having_attributes(mirroring: :vertical),
            prg_rom: Array.new(16_384, 0xA0),
            chr_rom: Array.new(8_192, 0xC0)
          )
        end
      end

      # The user's own dump (roms/smb3.nes, never committed): skipped where it is absent, as in CI. Header
      # 4E 45 53 1A 10 10 40 00, read on 2026-11-17 (plans/03-ines-cartridge-loader.md).
      context 'and it is the Super Mario Bros. 3 (USA) (Rev 1) dump', local_rom: 'smb3.nes' do
        it 'reads an MMC3 cartridge with 256 KiB of PRG ROM and 128 KiB of CHR ROM' do
          smb3_header = an_object_having_attributes(
            mapper_number: 4,
            mirroring: :horizontal,
            battery?: false,
            nes2?: false
          )

          expect(described_class.from_file(local_rom_path('smb3.nes'))).to have_attributes(
            header: smb3_header,
            prg_rom: have_attributes(size: 262_144),
            chr_rom: have_attributes(size: 131_072),
            trainer: []
          )
        end
      end
    end
  end
end
