# frozen_string_literal: true

# The windows through which a board shows a memory (PRG ROM to the CPU, CHR to the PPU), each an offset into it. A
# bank is a whole number of windows: MMC3 selects PRG in 8 KiB and CHR in 1 KiB and 2 KiB banks
# (https://www.nesdev.org/wiki/MMC3), UxROM and MMC1 16 KiB, AxROM 32 KiB, CNROM 8 KiB of CHR (plans 19 and 20). A
# bank past the end wraps around the memory, one window-sized piece at a time (plan 19, decision 5; plan 20, decision
# 9).
RSpec.describe Ruby::Nes::Mappers::BankWindows do
  describe '#select' do
    context 'when the bank is one window wide' do
      context 'and it is within the memory' do
        subject(:windows) do
          described_class.new(memory_size: 32_768, window_size: 8_192, window_count: 4, first_address: 0x8000)
        end

        before { windows.select(0xA000, 3, 8_192) }

        it 'shows the bank in the window at the address' do
          expect(windows.offsets[1]).to eq(24_576)
        end

        it 'leaves the other windows unchanged' do
          expect(windows.offsets.values_at(0, 2, 3)).to eq([0, 0, 0])
        end
      end

      context 'and it is past the end of the memory' do
        subject(:windows) do
          described_class.new(memory_size: 32_768, window_size: 8_192, window_count: 4, first_address: 0x8000)
        end

        before { windows.select(0xA000, 5, 8_192) }

        it 'shows the bank wrapped around the memory' do
          expect(windows.offsets[1]).to eq(8_192)
        end
      end
    end

    context 'when the bank is several windows wide' do
      context 'and it is within the memory' do
        subject(:windows) do
          described_class.new(memory_size: 8_192, window_size: 1_024, window_count: 8, first_address: 0x0000)
        end

        before { windows.select(0x1000, 1, 4_096) }

        it 'shows its pieces in order from the window at the address', :aggregate_failures do
          expect(windows.offsets.first(4)).to eq([0, 0, 0, 0])
          expect(windows.offsets.last(4)).to eq([4_096, 5_120, 6_144, 7_168])
        end
      end

      context 'and the memory is not a whole number of such banks' do
        # 80 KiB, as cpu_interrupts.nes: two 32 KiB banks and half of a third.
        subject(:windows) do
          described_class.new(memory_size: 81_920, window_size: 16_384, window_count: 2, first_address: 0x8000)
        end

        before { windows.select(0x8000, 2, 32_768) }

        it 'wraps each piece around the memory' do
          expect(windows.offsets).to eq([65_536, 0])
        end
      end
    end
  end

  describe '#last_bank' do
    context 'when the memory is a whole number of banks' do
      subject(:windows) do
        described_class.new(memory_size: 262_144, window_size: 8_192, window_count: 4, first_address: 0x8000)
      end

      it 'numbers the last bank' do
        expect(windows.last_bank(8_192)).to eq(31)
      end
    end

    context 'when the memory is not a whole number of banks' do
      subject(:windows) do
        described_class.new(memory_size: 81_920, window_size: 16_384, window_count: 2, first_address: 0x8000)
      end

      it 'numbers the last bank that starts in the memory' do
        expect(windows.last_bank(32_768)).to eq(2)
      end
    end
  end

  describe '#offsets' do
    subject(:windows) do
      described_class.new(memory_size: 8_192, window_size: 1_024, window_count: 8, first_address: 0x0000)
    end

    it 'starts with every window on the start of the memory' do
      expect(windows.offsets).to eq([0, 0, 0, 0, 0, 0, 0, 0])
    end
  end
end
