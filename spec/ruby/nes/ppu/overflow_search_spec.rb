# frozen_string_literal: true

# Step 3 of the sprite evaluation (https://www.nesdev.org/wiki/PPU_sprite_evaluation), once 8 sprites were found:
# "Starting at m = 0, evaluate OAM[n][m] as a Y-coordinate"; "If the value is in range, set the sprite overflow flag";
# "If the value is not in range, increment n **and** m (without carry). If n overflows to 0, go to 4" (the search
# ends). "The m increment is a hardware bug": after the first sprite the scan reads OAM "diagonally". Scanline 100,
# height 8: a byte of 100 is in range; OamContents' fill is out of range.
RSpec.describe Ruby::Nes::Ppu::OverflowSearch do
  describe '#found?' do
    subject(:search) { described_class.new(oam:) }

    context "when the first searched sprite's Y is in range" do
      let(:oam) { OamContents.build(8 => [100]) }

      it 'is true' do
        expect(search).to be_found(8, 100, 8)
      end
    end

    context "when the first searched sprite's Y is not in range" do
      context 'and byte 1 of the next sprite is in range' do
        let(:oam) { OamContents.build(9 => [0xF8, 100]) }

        it 'is true' do
          expect(search).to be_found(8, 100, 8)
        end
      end

      context 'and only the Y of the next sprite is in range' do
        let(:oam) { OamContents.build(9 => [100]) }

        it 'is false' do
          expect(search).not_to be_found(8, 100, 8)
        end
      end

      context 'and byte 0 of the fourth sprite after it is in range' do
        let(:oam) { OamContents.build(12 => [100]) }

        it 'is true' do
          expect(search).to be_found(8, 100, 8)
        end
      end

      context 'and no byte the scan reads is in range' do
        let(:oam) do
          OamContents.build(
            0 => [100, 100, 100, 100],
            1 => [100, 100, 100, 100],
            2 => [100, 100, 100, 100],
            3 => [100, 100, 100, 100],
            4 => [100, 100, 100, 100],
            5 => [100, 100, 100, 100],
            6 => [100, 100, 100, 100],
            7 => [100, 100, 100, 100]
          )
        end

        it 'is false' do
          expect(search).not_to be_found(8, 100, 8)
        end
      end
    end
  end
end
