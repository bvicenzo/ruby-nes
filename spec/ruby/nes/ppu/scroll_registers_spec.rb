# frozen_string_literal: true

# The "Register controls" table of https://www.nesdev.org/wiki/PPU_scrolling: v and t are 15 bits, x is 3 bits, w is
# the write toggle shared by $2005 and $2006; outside rendering $2007 "will add either 1 or 32 to v". The PPU's reset
# signal clears PPUSCROLL, PPUADDR and their latch, that is t, fine x and w, but "the VRAM address itself (V) is _not_
# cleared" (https://www.nesdev.org/wiki/PPU_power_up_state).
RSpec.describe Ruby::Nes::Ppu::ScrollRegisters do
  describe '#write_control' do
    subject(:scroll_registers) { described_class.new(temporary_address: 0x5555) }

    before { scroll_registers.write_control(0xFE) }

    it 'places bits 1-0 at t bits 11-10 and keeps the rest of t' do
      expect(scroll_registers.temporary_address).to eq(0x5955)
    end
  end

  describe '#write_scroll' do
    context 'when it is the first write' do
      subject(:scroll_registers) { described_class.new(temporary_address: 0x5555, vram_address: 0x1234) }

      before { scroll_registers.write_scroll(0x53) }

      it 'places bits 7-3 at t bits 4-0, bits 2-0 in x, and sets w', :aggregate_failures do
        expect(scroll_registers)
          .to have_attributes(temporary_address: 0x554A, fine_x: 0b011, second_write?: true, vram_address: 0x1234)
      end
    end

    context 'when it is the second write' do
      subject(:scroll_registers) do
        described_class.new(temporary_address: 0x5555, fine_x: 0b101, second_write: true, vram_address: 0x1234)
      end

      before { scroll_registers.write_scroll(0xAE) }

      it 'places bits 2-0 at t bits 14-12 and bits 7-3 at t bits 9-5, and clears w', :aggregate_failures do
        expect(scroll_registers)
          .to have_attributes(temporary_address: 0x66B5, fine_x: 0b101, second_write?: false, vram_address: 0x1234)
      end
    end
  end

  describe '#write_address' do
    context 'when it is the first write' do
      subject(:scroll_registers) { described_class.new(temporary_address: 0x5555, vram_address: 0x1234) }

      before { scroll_registers.write_address(0xEA) }

      it 'places bits 5-0 at t bits 13-8, clears t bit 14, and sets w', :aggregate_failures do
        expect(scroll_registers)
          .to have_attributes(temporary_address: 0x2A55, second_write?: true, vram_address: 0x1234)
      end
    end

    context 'when it is the second write' do
      subject(:scroll_registers) do
        described_class.new(temporary_address: 0x2A55, second_write: true, vram_address: 0x1234)
      end

      before { scroll_registers.write_address(0x9C) }

      it 'places the byte at t bits 7-0, copies t to v, and clears w', :aggregate_failures do
        expect(scroll_registers)
          .to have_attributes(temporary_address: 0x2A9C, vram_address: 0x2A9C, second_write?: false)
      end
    end
  end

  describe '#reset_write_toggle' do
    subject(:scroll_registers) { described_class.new(second_write: true) }

    before { scroll_registers.reset_write_toggle }

    it 'clears w' do
      expect(scroll_registers).not_to be_second_write
    end
  end

  describe '#reset' do
    subject(:scroll_registers) do
      described_class.new(vram_address: 0x2345, temporary_address: 0x5555, fine_x: 0x05, second_write: true)
    end

    before { scroll_registers.reset }

    it 'clears t and fine x', :aggregate_failures do
      expect(scroll_registers.temporary_address).to eq(0x0000)
      expect(scroll_registers.fine_x).to eq(0x00)
    end

    it 'clears w' do
      expect(scroll_registers).not_to be_second_write
    end

    it 'keeps v' do
      expect(scroll_registers.vram_address).to eq(0x2345)
    end
  end

  describe '#increment_vram_address' do
    context 'when v stays below $4000' do
      subject(:scroll_registers) { described_class.new(vram_address: 0x2000) }

      before { scroll_registers.increment_vram_address(1) }

      it 'adds the increment to v' do
        expect(scroll_registers.vram_address).to eq(0x2001)
      end
    end

    context 'when v goes past $3FFF' do
      subject(:scroll_registers) { described_class.new(vram_address: 0x3FFF) }

      before { scroll_registers.increment_vram_address(32) }

      it 'keeps the fifteenth bit' do
        expect(scroll_registers.vram_address).to eq(0x401F)
      end
    end

    context 'when v goes past $7FFF' do
      subject(:scroll_registers) { described_class.new(vram_address: 0x7FF0) }

      before { scroll_registers.increment_vram_address(32) }

      it 'wraps to 15 bits' do
        expect(scroll_registers.vram_address).to eq(0x0010)
      end
    end
  end

  # Rendering's updates of v ("Wrapping around", https://www.nesdev.org/wiki/PPU_scrolling). The comments spell v as
  # fine Y, nametable select, coarse Y and coarse X.
  describe '#increment_coarse_x' do
    context 'when coarse X is below 31' do
      # 5, 2, 22, 14.
      subject(:scroll_registers) do
        described_class.new(vram_address: 0x5ACE, temporary_address: 0x1234, fine_x: 0b011, second_write: true)
      end

      before { scroll_registers.increment_coarse_x }

      it 'adds 1 to coarse X and keeps the rest of v, t, x and w', :aggregate_failures do
        expect(scroll_registers)
          .to have_attributes(vram_address: 0x5ACF, temporary_address: 0x1234, fine_x: 0b011, second_write?: true)
      end
    end

    context 'when coarse X is 31' do
      context 'and the horizontal nametable is the left one' do
        # 5, 2, 22, 31.
        subject(:scroll_registers) { described_class.new(vram_address: 0x5ADF) }

        before { scroll_registers.increment_coarse_x }

        it 'clears coarse X and selects the right nametable' do
          # 5, 3, 22, 0.
          expect(scroll_registers.vram_address).to eq(0x5EC0)
        end
      end

      context 'and the horizontal nametable is the right one' do
        # 5, 3, 22, 31.
        subject(:scroll_registers) { described_class.new(vram_address: 0x5EDF) }

        before { scroll_registers.increment_coarse_x }

        it 'clears coarse X and selects the left nametable' do
          # 5, 2, 22, 0.
          expect(scroll_registers.vram_address).to eq(0x5AC0)
        end
      end
    end
  end

  describe '#increment_y' do
    context 'when fine Y is below 7' do
      # 5, 1, 22, 14.
      subject(:scroll_registers) { described_class.new(vram_address: 0x56CE) }

      before { scroll_registers.increment_y }

      it 'adds 1 to fine Y and keeps coarse Y' do
        # 6, 1, 22, 14.
        expect(scroll_registers.vram_address).to eq(0x66CE)
      end
    end

    context 'when fine Y is 7' do
      context 'and coarse Y is below 29' do
        # 7, 1, 22, 14.
        subject(:scroll_registers) { described_class.new(vram_address: 0x76CE) }

        before { scroll_registers.increment_y }

        it 'clears fine Y and adds 1 to coarse Y' do
          # 0, 1, 23, 14.
          expect(scroll_registers.vram_address).to eq(0x06EE)
        end
      end

      context 'and coarse Y is 29' do
        context 'and the vertical nametable is the top one' do
          # 7, 1, 29, 14.
          subject(:scroll_registers) { described_class.new(vram_address: 0x77AE) }

          before { scroll_registers.increment_y }

          it 'clears fine Y and coarse Y and selects the bottom nametable' do
            # 0, 3, 0, 14.
            expect(scroll_registers.vram_address).to eq(0x0C0E)
          end
        end

        context 'and the vertical nametable is the bottom one' do
          # 7, 3, 29, 14.
          subject(:scroll_registers) { described_class.new(vram_address: 0x7FAE) }

          before { scroll_registers.increment_y }

          it 'clears fine Y and coarse Y and selects the top nametable' do
            # 0, 1, 0, 14.
            expect(scroll_registers.vram_address).to eq(0x040E)
          end
        end
      end

      context 'and coarse Y is 30' do
        # 7, 1, 30, 14.
        subject(:scroll_registers) { described_class.new(vram_address: 0x77CE) }

        before { scroll_registers.increment_y }

        it 'clears fine Y and adds 1 to coarse Y' do
          # 0, 1, 31, 14.
          expect(scroll_registers.vram_address).to eq(0x07EE)
        end
      end

      context 'and coarse Y is 31' do
        # 7, 1, 31, 14.
        subject(:scroll_registers) { described_class.new(vram_address: 0x77EE) }

        before { scroll_registers.increment_y }

        it 'clears fine Y and coarse Y and keeps the nametable' do
          # 0, 1, 0, 14.
          expect(scroll_registers.vram_address).to eq(0x040E)
        end
      end
    end
  end

  describe '#copy_horizontal_position' do
    # v: 7, 2, 31, 10; t: 0, 1, 0, 21.
    subject(:scroll_registers) { described_class.new(vram_address: 0x7BEA, temporary_address: 0x0415) }

    before { scroll_registers.copy_horizontal_position }

    it 'takes bits 10 and 4-0 from t and keeps the other bits of v' do
      # 7, 3, 31, 21.
      expect(scroll_registers.vram_address).to eq(0x7FF5)
    end
  end

  describe '#copy_vertical_position' do
    # v: 2, 1, 10, 21; t: 5, 2, 21, 0.
    subject(:scroll_registers) { described_class.new(vram_address: 0x2555, temporary_address: 0x5AA0) }

    before { scroll_registers.copy_vertical_position }

    it 'takes bits 14-11 and 9-5 from t and keeps the other bits of v' do
      # 5, 3, 21, 21.
      expect(scroll_registers.vram_address).to eq(0x5EB5)
    end
  end
end
