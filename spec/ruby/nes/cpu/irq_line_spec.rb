# frozen_string_literal: true

# The CPU's IRQ input (https://www.nesdev.org/wiki/CPU_interrupts), "connected to a level detector": the signal is
# raised "as long as the IRQ input is low during the preceding cycle's φ2". It is a wired-OR, as the hardware's
# open-collector line (architecture decision 25): each source asserts and releases its own bit, and the line is
# asserted while any source asserts it. Each change carries the CPU cycle it happened on (plan 22, decision 6), so a
# poll sees the line as it stood before its poll cycle: asserted before it, and not released before it. A release on
# the poll cycle or later (a $4015 read or a $E000 write on an instruction's last cycle) came after the poll.
RSpec.describe Ruby::Nes::Cpu::IrqLine do
  describe '#asserted_at?' do
    context 'when no source asserted it' do
      context 'and no source released it' do
        subject(:irq_line) { described_class.new }

        it 'sees the line released' do
          expect(irq_line).not_to be_asserted_at(10)
        end
      end

      context 'but a source released it' do
        subject(:irq_line) { described_class.new.tap { |line| line.release(first_source, 9) } }

        let(:first_source) { 0x01 }

        it 'sees the line released' do
          expect(irq_line).not_to be_asserted_at(10)
        end
      end
    end

    context 'when a source asserted it' do
      context 'but on the poll cycle' do
        subject(:irq_line) { described_class.new.tap { |line| line.assert(first_source, 9) } }

        let(:first_source) { 0x01 }

        it 'sees the line released' do
          expect(irq_line).not_to be_asserted_at(9)
        end
      end

      context 'but it was released and asserted again on the poll cycle' do
        subject(:irq_line) do
          described_class.new.tap do |line|
            line.assert(first_source, 5)
            line.release(first_source, 6)
            line.assert(first_source, 9)
          end
        end

        let(:first_source) { 0x01 }

        it 'sees the line released' do
          expect(irq_line).not_to be_asserted_at(9)
        end
      end

      context 'and before the poll cycle' do
        context 'but every source released it before the poll cycle' do
          subject(:irq_line) do
            described_class.new.tap do |line|
              line.assert(first_source, 7)
              line.release(first_source, 8)
            end
          end

          let(:first_source) { 0x01 }

          it 'sees the line released' do
            expect(irq_line).not_to be_asserted_at(9)
          end
        end

        context 'and every source released it on the poll cycle' do
          subject(:irq_line) do
            described_class.new.tap do |line|
              line.assert(first_source, 7)
              line.release(first_source, 9)
            end
          end

          let(:first_source) { 0x01 }

          it 'sees the line asserted' do
            expect(irq_line).to be_asserted_at(9)
          end
        end

        context 'and it is still asserted' do
          context 'and only that source asserted it' do
            subject(:irq_line) { described_class.new.tap { |line| line.assert(first_source, 8) } }

            let(:first_source) { 0x01 }

            it 'sees the line asserted' do
              expect(irq_line).to be_asserted_at(9)
            end
          end

          context 'and the same source asserted it again after the poll cycle' do
            subject(:irq_line) do
              described_class.new.tap do |line|
                line.assert(first_source, 8)
                line.assert(first_source, 10)
              end
            end

            let(:first_source) { 0x01 }

            it 'sees the line asserted' do
              expect(irq_line).to be_asserted_at(9)
            end
          end

          context 'and another source asserted it after the poll cycle' do
            subject(:irq_line) do
              described_class.new.tap do |line|
                line.assert(first_source, 8)
                line.assert(second_source, 10)
              end
            end

            let(:first_source) { 0x01 }
            let(:second_source) { 0x02 }

            it 'sees the line asserted' do
              expect(irq_line).to be_asserted_at(9)
            end
          end

          context 'and another source that never asserted it released it' do
            subject(:irq_line) do
              described_class.new.tap do |line|
                line.assert(first_source, 7)
                line.release(second_source, 8)
              end
            end

            let(:first_source) { 0x01 }
            let(:second_source) { 0x02 }

            it 'sees the line asserted' do
              expect(irq_line).to be_asserted_at(9)
            end
          end

          context 'and one of two sources released it before the poll cycle' do
            subject(:irq_line) do
              described_class.new.tap do |line|
                line.assert(first_source, 6)
                line.assert(second_source, 7)
                line.release(first_source, 8)
              end
            end

            let(:first_source) { 0x01 }
            let(:second_source) { 0x02 }

            it 'sees the line asserted' do
              expect(irq_line).to be_asserted_at(9)
            end
          end
        end
      end
    end
  end
end
