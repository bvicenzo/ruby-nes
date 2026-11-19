# frozen_string_literal: true

# Steps 1-2 of the sprite evaluation (https://www.nesdev.org/wiki/PPU_sprite_evaluation): "Starting at n = 0, read a
# sprite's Y-coordinate"; "If Y-coordinate is in range, copy remaining bytes of sprite data (OAM[n][1] thru OAM[n][3])
# into secondary OAM"; "If exactly 8 sprites have been found, disable writes to secondary OAM because it is full", then
# the search for a ninth starts at the next sprite (step 3, Ppu::OverflowSearch) and sets "the sprite overflow flag".
# Secondary OAM "is initialized to $FF" first. Sprite 0 in range is tracked apart (https://www.nesdev.org/wiki/PPU_OAM).
# Height: 8, or 16 with PPUCTRL bit 5 (https://www.nesdev.org/wiki/PPU_registers). Scanline 100: a sprite whose Y is
# 100 covers it; OamContents' fill does not.
RSpec.describe Ruby::Nes::Ppu::SpriteEvaluation do
  describe '#evaluate' do
    subject(:evaluation) { described_class.new(oam:, secondary_oam:, status:, overflow_search:, sprite_height:) }

    let(:secondary_oam) do
      instance_double(Ruby::Nes::Ppu::SecondaryOam, clear: nil, add: nil, select_sprite_zero: nil)
    end
    let(:status) { instance_double(Ruby::Nes::Ppu::SpriteStatus, overflow_found: nil) }

    context 'when no sprite covers the scanline' do
      let(:oam) { OamContents.build }
      let(:overflow_search) { instance_double(Ruby::Nes::Ppu::OverflowSearch) }
      let(:sprite_height) { 8 }

      before { evaluation.evaluate(100) }

      it 'clears secondary OAM and adds no sprite', :aggregate_failures do
        expect(secondary_oam).to have_received(:clear)
        expect(secondary_oam).not_to have_received(:add)
      end
    end

    context 'when one sprite covers the scanline' do
      let(:overflow_search) { instance_double(Ruby::Nes::Ppu::OverflowSearch) }
      let(:sprite_height) { 8 }

      context 'and it is not sprite 0' do
        let(:oam) { OamContents.build(5 => [100, 0x21, 0x43, 0x80]) }

        before { evaluation.evaluate(100) }

        it 'adds its four bytes after clearing secondary OAM', :aggregate_failures do
          expect(secondary_oam).to have_received(:clear).ordered
          expect(secondary_oam).to have_received(:add).with(100, 0x21, 0x43, 0x80).once.ordered
        end

        it 'does not select sprite 0' do
          expect(secondary_oam).not_to have_received(:select_sprite_zero)
        end
      end

      context 'and it is sprite 0' do
        let(:oam) { OamContents.build(0 => [100, 0x21, 0x43, 0x80]) }

        before { evaluation.evaluate(100) }

        it 'adds it and selects sprite 0', :aggregate_failures do
          expect(secondary_oam).to have_received(:add).with(100, 0x21, 0x43, 0x80).once
          expect(secondary_oam).to have_received(:select_sprite_zero)
        end
      end
    end

    context 'when a sprite covers the scanline only within the 8×16 height' do
      let(:oam) { OamContents.build(5 => [90, 0x21, 0x43, 0x80]) }
      let(:overflow_search) { instance_double(Ruby::Nes::Ppu::OverflowSearch) }

      context 'but the sprites are 8×8' do
        let(:sprite_height) { 8 }

        before { evaluation.evaluate(100) }

        it 'adds no sprite' do
          expect(secondary_oam).not_to have_received(:add)
        end
      end

      context 'and the sprites are 8×16' do
        let(:sprite_height) { 16 }

        before { evaluation.evaluate(100) }

        it 'adds it' do
          expect(secondary_oam).to have_received(:add).with(90, 0x21, 0x43, 0x80).once
        end
      end
    end

    context 'when eight sprites cover the scanline' do
      let(:sprite_height) { 8 }

      context 'and the eighth is the last sprite of OAM' do
        let(:oam) do
          OamContents.build(
            56 => [100, 0x56, 0x00, 0x10],
            57 => [100, 0x57, 0x00, 0x20],
            58 => [100, 0x58, 0x00, 0x30],
            59 => [100, 0x59, 0x00, 0x40],
            60 => [100, 0x60, 0x00, 0x50],
            61 => [100, 0x61, 0x00, 0x60],
            62 => [100, 0x62, 0x00, 0x70],
            63 => [100, 0x63, 0x00, 0x80]
          )
        end
        let(:overflow_search) { instance_double(Ruby::Nes::Ppu::OverflowSearch, found?: true) }

        before { evaluation.evaluate(100) }

        it 'adds the eight in OAM order', :aggregate_failures do
          expect(secondary_oam).to have_received(:add).with(100, 0x56, 0x00, 0x10).ordered
          expect(secondary_oam).to have_received(:add).with(100, 0x57, 0x00, 0x20).ordered
          expect(secondary_oam).to have_received(:add).with(100, 0x58, 0x00, 0x30).ordered
          expect(secondary_oam).to have_received(:add).with(100, 0x59, 0x00, 0x40).ordered
          expect(secondary_oam).to have_received(:add).with(100, 0x60, 0x00, 0x50).ordered
          expect(secondary_oam).to have_received(:add).with(100, 0x61, 0x00, 0x60).ordered
          expect(secondary_oam).to have_received(:add).with(100, 0x62, 0x00, 0x70).ordered
          expect(secondary_oam).to have_received(:add).with(100, 0x63, 0x00, 0x80).ordered
        end

        it 'does not search for a ninth' do
          expect(overflow_search).not_to have_received(:found?)
        end
      end

      context 'and sprites follow the eighth' do
        let(:oam) do
          OamContents.build(
            0 => [100, 0x00, 0x00, 0x10],
            1 => [100, 0x01, 0x00, 0x20],
            2 => [100, 0x02, 0x00, 0x30],
            3 => [100, 0x03, 0x00, 0x40],
            4 => [100, 0x04, 0x00, 0x50],
            5 => [100, 0x05, 0x00, 0x60],
            6 => [100, 0x06, 0x00, 0x70],
            7 => [100, 0x07, 0x00, 0x80],
            8 => [100, 0x08, 0x00, 0x90]
          )
        end

        context 'but the search finds no ninth' do
          let(:overflow_search) { instance_double(Ruby::Nes::Ppu::OverflowSearch, found?: false) }

          before { evaluation.evaluate(100) }

          it 'leaves the status alone' do
            expect(status).not_to have_received(:overflow_found)
          end
        end

        context 'and the search finds a ninth' do
          let(:overflow_search) { instance_double(Ruby::Nes::Ppu::OverflowSearch, found?: true) }

          before { evaluation.evaluate(100) }

          it 'searches from the sprite after the eighth' do
            expect(overflow_search).to have_received(:found?).with(8, 100, 8)
          end

          it 'adds only the first eight', :aggregate_failures do
            expect(secondary_oam).to have_received(:add).exactly(8).times
            expect(secondary_oam).not_to have_received(:add).with(100, 0x08, 0x00, 0x90)
          end

          it 'tells the status the sprites overflowed' do
            expect(status).to have_received(:overflow_found)
          end
        end
      end
    end
  end
end
