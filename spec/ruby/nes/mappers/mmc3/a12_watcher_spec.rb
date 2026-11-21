# frozen_string_literal: true

# MMC3 clocks its counter on "a rising edge after the line has remained low for three falling edges of M2", "no matter
# what caused it" (https://www.nesdev.org/wiki/MMC3#IRQ_Specifics); A12 is address bit 12 ($1000). The watcher sees
# every address that reaches the board and counts M2 cycles as the PPU's elapsed dots divided by 3 (plan 21, decision
# 2). A12 starts low, low since dot 0: a convention, no page says what the PPU's bus holds at power-up (plan 21,
# decision 13). The low period starts at the first low address after a high one. Dots below are elapsed dots; a CPU cycle is 3 of them.
RSpec.describe Ruby::Nes::Mappers::Mmc3::A12Watcher do
  describe '#watch' do
    context 'when A12 is low' do
      context 'and it was high' do
        subject(:watcher) { described_class.new(counter:, ppu:) }

        let(:counter) { instance_double(Ruby::Nes::Mappers::Mmc3::IrqCounter, clock: nil) }
        let(:ppu) { instance_double(Ruby::Nes::Ppu) }

        before do
          allow(ppu).to receive(:elapsed_dots).and_return(0)
          watcher.watch(0x1000)
          allow(ppu).to receive(:elapsed_dots).and_return(30)
          watcher.watch(0x0FF0)
        end

        it 'clocks nothing' do
          expect(counter).not_to have_received(:clock)
        end
      end

      context 'and it was already low' do
        # High at dot 0, low from dot 3 (cycle 1) and again at dot 9 (cycle 3), high at dot 12 (cycle 4): 3 cycles from
        # the first low address, 1 from the second.
        subject(:watcher) { described_class.new(counter:, ppu:) }

        let(:counter) { instance_double(Ruby::Nes::Mappers::Mmc3::IrqCounter, clock: nil) }
        let(:ppu) { instance_double(Ruby::Nes::Ppu) }

        before do
          allow(ppu).to receive(:elapsed_dots).and_return(0)
          watcher.watch(0x1000)
          allow(ppu).to receive(:elapsed_dots).and_return(3)
          watcher.watch(0x0000)
          allow(ppu).to receive(:elapsed_dots).and_return(9)
          watcher.watch(0x0000)
          allow(ppu).to receive(:elapsed_dots).and_return(12)
          watcher.watch(0x1000)
        end

        it 'keeps the low period from its first low address' do
          expect(counter).to have_received(:clock).once.with(4)
        end
      end
    end

    context 'when A12 is high' do
      context 'and it was high' do
        subject(:watcher) { described_class.new(counter:, ppu:) }

        let(:counter) { instance_double(Ruby::Nes::Mappers::Mmc3::IrqCounter, clock: nil) }
        let(:ppu) { instance_double(Ruby::Nes::Ppu) }

        before do
          allow(ppu).to receive(:elapsed_dots).and_return(0)
          watcher.watch(0x1000)
          allow(ppu).to receive(:elapsed_dots).and_return(30)
          watcher.watch(0x1FF0)
        end

        it 'clocks nothing' do
          expect(counter).not_to have_received(:clock)
        end
      end

      context 'and it was low' do
        context 'but for fewer than 3 M2 cycles' do
          # Low from dot 3 (cycle 1), high at dot 9 (cycle 3).
          subject(:watcher) { described_class.new(counter:, ppu:) }

          let(:counter) { instance_double(Ruby::Nes::Mappers::Mmc3::IrqCounter, clock: nil) }
          let(:ppu) { instance_double(Ruby::Nes::Ppu) }

          before do
            allow(ppu).to receive(:elapsed_dots).and_return(0)
            watcher.watch(0x1000)
            allow(ppu).to receive(:elapsed_dots).and_return(3)
            watcher.watch(0x0000)
            allow(ppu).to receive(:elapsed_dots).and_return(9)
            watcher.watch(0x1000)
          end

          it 'clocks nothing' do
            expect(counter).not_to have_received(:clock)
          end
        end

        context 'and for exactly 3 M2 cycles' do
          # Low from dot 3 (cycle 1), high at dot 12 (cycle 4).
          subject(:watcher) { described_class.new(counter:, ppu:) }

          let(:counter) { instance_double(Ruby::Nes::Mappers::Mmc3::IrqCounter, clock: nil) }
          let(:ppu) { instance_double(Ruby::Nes::Ppu) }

          before do
            allow(ppu).to receive(:elapsed_dots).and_return(0)
            watcher.watch(0x1000)
            allow(ppu).to receive(:elapsed_dots).and_return(3)
            watcher.watch(0x0000)
            allow(ppu).to receive(:elapsed_dots).and_return(12)
            watcher.watch(0x1000)
          end

          it 'clocks the counter on the cycle of the rise' do
            expect(counter).to have_received(:clock).once.with(4)
          end
        end

        context 'and for more than 3 M2 cycles' do
          subject(:watcher) { described_class.new(counter:, ppu:) }

          let(:counter) { instance_double(Ruby::Nes::Mappers::Mmc3::IrqCounter, clock: nil) }
          let(:ppu) { instance_double(Ruby::Nes::Ppu) }

          before do
            allow(ppu).to receive(:elapsed_dots).and_return(0)
            watcher.watch(0x1000)
            allow(ppu).to receive(:elapsed_dots).and_return(3)
            watcher.watch(0x0000)
            allow(ppu).to receive(:elapsed_dots).and_return(300)
            watcher.watch(0x1000)
          end

          it 'clocks the counter on the cycle of the rise' do
            expect(counter).to have_received(:clock).once.with(100)
          end
        end
      end
    end

    context 'when the first address since power-up has A12 high, 3 M2 cycles in' do
      subject(:watcher) { described_class.new(counter:, ppu:) }

      let(:counter) { instance_double(Ruby::Nes::Mappers::Mmc3::IrqCounter, clock: nil) }
      let(:ppu) { instance_double(Ruby::Nes::Ppu, elapsed_dots: 9) }

      before { watcher.watch(0x1000) }

      it 'clocks the counter' do
        expect(counter).to have_received(:clock).once
      end
    end
  end
end
