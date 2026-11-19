# frozen_string_literal: true

# Palette RAM facts: "Each byte in this palette RAM contains a 6-bit color value", and "entry 0 of each palette is also
# unique in that its color value is shared between the background and sprite palettes, so writing to either one
# updates the same internal storage" (https://www.nesdev.org/wiki/PPU_palettes); "$3F20-$3FFF ... Mirrors of
# $3F00-$3F1F" (https://www.nesdev.org/wiki/PPU_memory_map).
RSpec.describe Ruby::Nes::PpuBus::PaletteRam do
  describe '#read' do
    subject(:palette_ram) { described_class.new }

    context 'when nothing was written' do
      it 'returns 0' do
        expect(palette_ram.read(0x3F05)).to eq(0x00)
      end
    end

    context 'when the address is in $3F00-$3F1F' do
      before { palette_ram.write(0x3F05, 0x2A) }

      it 'returns the colour written at that address' do
        expect(palette_ram.read(0x3F05)).to eq(0x2A)
      end
    end

    context 'when the address mirrors $3F00-$3F1F' do
      context 'and it is $3F20' do
        before { palette_ram.write(0x3F00, 0x0F) }

        it 'returns the colour written at $3F00' do
          expect(palette_ram.read(0x3F20)).to eq(0x0F)
        end
      end

      context 'and it is $3FFF' do
        before { palette_ram.write(0x3F1F, 0x30) }

        it 'returns the colour written at $3F1F' do
          expect(palette_ram.read(0x3FFF)).to eq(0x30)
        end
      end
    end

    context 'when the address is entry 0 of a sprite palette' do
      context 'and it is $3F10' do
        before { palette_ram.write(0x3F00, 0x11) }

        it 'returns the colour written at $3F00' do
          expect(palette_ram.read(0x3F10)).to eq(0x11)
        end
      end

      context 'and it is $3F14' do
        before { palette_ram.write(0x3F04, 0x12) }

        it 'returns the colour written at $3F04' do
          expect(palette_ram.read(0x3F14)).to eq(0x12)
        end
      end

      context 'and it is $3F18' do
        before { palette_ram.write(0x3F08, 0x13) }

        it 'returns the colour written at $3F08' do
          expect(palette_ram.read(0x3F18)).to eq(0x13)
        end
      end

      context 'and it is $3F1C' do
        before { palette_ram.write(0x3F0C, 0x14) }

        it 'returns the colour written at $3F0C' do
          expect(palette_ram.read(0x3F1C)).to eq(0x14)
        end
      end
    end

    context 'when the address is another entry of a sprite palette' do
      before do
        palette_ram.write(0x3F01, 0x21)
        palette_ram.write(0x3F11, 0x22)
      end

      it 'returns its own colour, not the background entry 16 below' do
        expect(palette_ram.read(0x3F11)).to eq(0x22)
      end
    end
  end

  describe '#write' do
    subject(:palette_ram) { described_class.new }

    context 'when the colour fits in 6 bits' do
      before { palette_ram.write(0x3F05, 0x3F) }

      it 'is read back whole' do
        expect(palette_ram.read(0x3F05)).to eq(0x3F)
      end
    end

    context 'when the colour has bits 7-6 set' do
      before { palette_ram.write(0x3F05, 0xFF) }

      it 'is read back with its low 6 bits only' do
        expect(palette_ram.read(0x3F05)).to eq(0x3F)
      end
    end

    context 'when the address mirrors $3F00-$3F1F' do
      context 'and it is $3F20' do
        before { palette_ram.write(0x3F20, 0x0F) }

        it 'is read at $3F00' do
          expect(palette_ram.read(0x3F00)).to eq(0x0F)
        end
      end

      context 'and it is $3FFF' do
        before { palette_ram.write(0x3FFF, 0x30) }

        it 'is read at $3F1F' do
          expect(palette_ram.read(0x3F1F)).to eq(0x30)
        end
      end
    end

    context 'when the address is entry 0 of a sprite palette' do
      context 'and it is $3F10' do
        before { palette_ram.write(0x3F10, 0x11) }

        it 'is read at $3F00' do
          expect(palette_ram.read(0x3F00)).to eq(0x11)
        end
      end

      context 'and it is $3F14' do
        before { palette_ram.write(0x3F14, 0x12) }

        it 'is read at $3F04' do
          expect(palette_ram.read(0x3F04)).to eq(0x12)
        end
      end

      context 'and it is $3F18' do
        before { palette_ram.write(0x3F18, 0x13) }

        it 'is read at $3F08' do
          expect(palette_ram.read(0x3F08)).to eq(0x13)
        end
      end

      context 'and it is $3F1C' do
        before { palette_ram.write(0x3F1C, 0x14) }

        it 'is read at $3F0C' do
          expect(palette_ram.read(0x3F0C)).to eq(0x14)
        end
      end
    end

    context 'when the address is another entry of a sprite palette' do
      before do
        palette_ram.write(0x3F01, 0x21)
        palette_ram.write(0x3F11, 0x22)
      end

      it 'leaves the background entry 16 below unchanged' do
        expect(palette_ram.read(0x3F01)).to eq(0x21)
      end
    end
  end
end
