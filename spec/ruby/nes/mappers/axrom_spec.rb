# frozen_string_literal: true

RSpec.describe Ruby::Nes::Mappers::Axrom do
  describe '.new' do
    context 'when the PRG ROM is not a multiple of 32 KiB' do
      let(:cartridge) { Cartridges.build(prg_rom: Array.new(49_152, 0xFF)) }

      it 'raises InvalidCartridge naming the PRG ROM size' do
        expect { described_class.new(cartridge) }
          .to raise_error(Ruby::Nes::Mappers::InvalidCartridge, /PRG ROM of 49152 bytes/)
      end
    end

    context 'when the PRG ROM is a multiple of 32 KiB' do
      let(:cartridge) { Cartridges.build(prg_rom: Array.new(65_536, 0xFF)) }

      it 'builds the board' do
        expect { described_class.new(cartridge) }.not_to raise_error
      end
    end
  end

  describe '#cpu_read' do
    subject(:axrom) { described_class.new(cartridge) }

    # 128 KiB, four 32 KiB banks; each holds its number at $BFFF and $20 plus its number at $C000.
    let(:cartridge) { Cartridges.build(prg_rom: 4.times.flat_map { |bank| [*padding, bank, 0x20 + bank, *padding] }) }
    let(:padding) { Array.new(16_383, 0xFF) }

    context 'when the address is in the PRG RAM range' do
      it 'returns the data bus value' do
        expect(axrom.cpu_read(0x6000, 0x5A)).to eq(0x5A)
      end
    end

    context 'when the address is in PRG ROM' do
      context 'and it is in the lower half' do
        it "returns the first bank's lower half" do
          expect(axrom.cpu_read(0xBFFF, 0x5A)).to eq(0x00)
        end
      end

      context 'and it is in the upper half' do
        it "returns the first bank's upper half" do
          expect(axrom.cpu_read(0xC000, 0x5A)).to eq(0x20)
        end
      end
    end
  end

  describe '#mirroring' do
    subject(:axrom) { described_class.new(cartridge) }

    let(:cartridge) { Cartridges.build(prg_rom: Array.new(32_768, 0xFF), mirroring: :vertical) }

    context 'when no bank was selected yet' do
      it 'is the lower single screen, whatever the header says' do
        expect(axrom.mirroring).to eq(:single_screen_lower)
      end
    end

    context 'when a write clears bit 4 while the upper screen is shown' do
      before do
        axrom.cpu_write(0x8000, 0x10)
        axrom.cpu_write(0x8000, 0x00)
      end

      it 'is the lower single screen' do
        expect(axrom.mirroring).to eq(:single_screen_lower)
      end
    end

    context 'when a write sets bit 4' do
      before { axrom.cpu_write(0x8000, 0x10) }

      it 'is the upper single screen' do
        expect(axrom.mirroring).to eq(:single_screen_upper)
      end
    end

    # The nametables start on the lower screen, where $2005 is written; bit 4 then shows the upper one.
    context 'when its nametables were given' do
      let!(:nametables) { Ruby::Nes::PpuBus::Nametables.new(mapper: axrom) }

      before do
        nametables.write(0x2005, 0x11)
        axrom.cpu_write(0x8000, 0x10)
      end

      it 'tells them the screen selected' do
        expect(nametables.read(0x2005)).to eq(0x00)
      end
    end
  end

  describe '#cpu_write' do
    subject(:axrom) { described_class.new(cartridge) }

    context 'when the address is in PRG ROM' do
      context 'and bit 3 is set' do
        # 512 KiB, sixteen 32 KiB banks, each holding its number at $BFFF: $08 would reach bank 8 with bit 3.
        let(:cartridge) { Cartridges.build(prg_rom: 16.times.flat_map { |bank| [*padding, bank, 0xFF, *padding] }) }
        let(:padding) { Array.new(16_383, 0xFF) }

        before { axrom.cpu_write(0x8000, 0x08) }

        it 'selects the bank of bits 2-0' do
          expect(axrom.cpu_read(0xBFFF, 0x5A)).to eq(0)
        end
      end

      context 'and the bank exceeds the PRG ROM' do
        # 128 KiB, four 32 KiB banks, each holding its number at $BFFF.
        let(:cartridge) { Cartridges.build(prg_rom: 4.times.flat_map { |bank| [*padding, bank, 0xFF, *padding] }) }
        let(:padding) { Array.new(16_383, 0xFF) }

        before { axrom.cpu_write(0x8000, 6) }

        it 'selects the bank wrapped by the PRG ROM size' do
          expect(axrom.cpu_read(0xBFFF, 0x5A)).to eq(2)
        end
      end

      context 'and the bank is in the PRG ROM' do
        # 128 KiB, four 32 KiB banks; each holds its number at $BFFF and $20 plus its number at $C000.
        let(:cartridge) do
          Cartridges.build(prg_rom: 4.times.flat_map { |bank| [*padding, bank, 0x20 + bank, *padding] })
        end
        let(:padding) { Array.new(16_383, 0xFF) }

        context 'and the address is $8000' do
          before { axrom.cpu_write(0x8000, 3) }

          it "shows that bank's lower half" do
            expect(axrom.cpu_read(0xBFFF, 0x5A)).to eq(3)
          end

          it "shows that bank's upper half" do
            expect(axrom.cpu_read(0xC000, 0x5A)).to eq(0x23)
          end
        end

        context 'and the address is $FFFF' do
          before { axrom.cpu_write(0xFFFF, 3) }

          it 'shows that bank' do
            expect(axrom.cpu_read(0xBFFF, 0x5A)).to eq(3)
          end
        end

        context 'and the ROM byte at the address clears bits of the value' do
          # $BFFF holds bank 0's number, $00: ANDed with it, any bank would become 0.
          before { axrom.cpu_write(0xBFFF, 3) }

          it 'selects the bank written' do
            expect(axrom.cpu_read(0xBFFF, 0x5A)).to eq(3)
          end
        end
      end
    end
  end
end
