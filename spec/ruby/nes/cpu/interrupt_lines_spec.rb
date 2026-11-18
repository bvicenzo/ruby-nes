# frozen_string_literal: true

# The CPU's two interrupt inputs (https://www.nesdev.org/wiki/CPU_interrupts). NMI is edge-sensitive: the edge detector
# notices the line going from released to asserted, and the internal signal "stays high until the NMI has been
# handled", so releasing the line does not cancel it and holding it asserted does not repeat it. IRQ is
# level-sensitive: it is taken while the line is asserted, unless I is set ("When set, IRQ interrupts are inhibited.
# NMI, BRK, and reset are not affected", https://www.nesdev.org/wiki/Status_flags). "If both an NMI and an IRQ are
# pending at the end of an instruction, the NMI will be handled". Both lines start released.
RSpec.describe Ruby::Nes::Cpu::InterruptLines do
  describe '#acknowledge' do
    context 'when the NMI line stays released' do
      context 'and the IRQ line stays released' do
        subject(:interrupt_lines) { described_class.new(status:) }

        let(:status) { Ruby::Nes::Cpu::Status.new }

        it 'returns nothing' do
          expect(interrupt_lines.acknowledge).to be_nil
        end
      end

      context 'and the IRQ line was asserted and released again' do
        subject(:interrupt_lines) do
          described_class.new(status:).tap do |lines|
            lines.irq_line = true
            lines.irq_line = false
          end
        end

        let(:status) { Ruby::Nes::Cpu::Status.new }

        it 'returns nothing' do
          expect(interrupt_lines.acknowledge).to be_nil
        end
      end

      context 'and the IRQ line is asserted' do
        context 'but interrupt disable is set' do
          subject(:interrupt_lines) { described_class.new(status:).tap { |lines| lines.irq_line = true } }

          let(:status) { Ruby::Nes::Cpu::Status.new.tap { |status| status.interrupt_disable = true } }

          it 'returns nothing' do
            expect(interrupt_lines.acknowledge).to be_nil
          end
        end

        context 'and interrupt disable is clear' do
          context 'and the IRQ was already acknowledged' do
            subject(:interrupt_lines) do
              described_class.new(status:).tap do |lines|
                lines.irq_line = true
                lines.acknowledge
              end
            end

            let(:status) { Ruby::Nes::Cpu::Status.new }

            it 'returns the IRQ vector' do
              expect(interrupt_lines.acknowledge).to eq(0xFFFE)
            end
          end

          context 'and the IRQ was not acknowledged yet' do
            subject(:interrupt_lines) { described_class.new(status:).tap { |lines| lines.irq_line = true } }

            let(:status) { Ruby::Nes::Cpu::Status.new }

            it 'returns the IRQ vector' do
              expect(interrupt_lines.acknowledge).to eq(0xFFFE)
            end
          end
        end
      end
    end

    context 'when the NMI line rose from released to asserted' do
      context 'and the NMI was already acknowledged' do
        context 'and the line is asserted again without being released' do
          subject(:interrupt_lines) do
            described_class.new(status:).tap do |lines|
              lines.nmi_line = true
              lines.acknowledge
              lines.nmi_line = true
            end
          end

          let(:status) { Ruby::Nes::Cpu::Status.new }

          it 'returns nothing' do
            expect(interrupt_lines.acknowledge).to be_nil
          end
        end

        context 'and the line is released and asserted again' do
          subject(:interrupt_lines) do
            described_class.new(status:).tap do |lines|
              lines.nmi_line = true
              lines.acknowledge
              lines.nmi_line = false
              lines.nmi_line = true
            end
          end

          let(:status) { Ruby::Nes::Cpu::Status.new }

          it 'returns the NMI vector' do
            expect(interrupt_lines.acknowledge).to eq(0xFFFA)
          end
        end
      end

      context 'and the line was released before acknowledging' do
        subject(:interrupt_lines) do
          described_class.new(status:).tap do |lines|
            lines.nmi_line = true
            lines.nmi_line = false
          end
        end

        let(:status) { Ruby::Nes::Cpu::Status.new }

        it 'returns the NMI vector' do
          expect(interrupt_lines.acknowledge).to eq(0xFFFA)
        end
      end

      context 'and the line is still asserted' do
        context 'and interrupt disable is set' do
          context 'and the IRQ line is released' do
            subject(:interrupt_lines) { described_class.new(status:).tap { |lines| lines.nmi_line = true } }

            let(:status) { Ruby::Nes::Cpu::Status.new.tap { |status| status.interrupt_disable = true } }

            it 'returns the NMI vector' do
              expect(interrupt_lines.acknowledge).to eq(0xFFFA)
            end
          end

          context 'and the IRQ line is asserted' do
            subject(:interrupt_lines) do
              described_class.new(status:).tap do |lines|
                lines.nmi_line = true
                lines.irq_line = true
              end
            end

            let(:status) { Ruby::Nes::Cpu::Status.new.tap { |status| status.interrupt_disable = true } }

            it 'returns the NMI vector' do
              expect(interrupt_lines.acknowledge).to eq(0xFFFA)
            end
          end
        end

        context 'and interrupt disable is clear' do
          context 'and the IRQ line is released' do
            subject(:interrupt_lines) { described_class.new(status:).tap { |lines| lines.nmi_line = true } }

            let(:status) { Ruby::Nes::Cpu::Status.new }

            it 'returns the NMI vector' do
              expect(interrupt_lines.acknowledge).to eq(0xFFFA)
            end
          end

          context 'and the IRQ line is asserted' do
            subject(:interrupt_lines) do
              described_class.new(status:).tap do |lines|
                lines.nmi_line = true
                lines.irq_line = true
              end
            end

            let(:status) { Ruby::Nes::Cpu::Status.new }

            it 'returns the NMI vector' do
              expect(interrupt_lines.acknowledge).to eq(0xFFFA)
            end
          end
        end
      end
    end
  end

  describe '#discard_pending_nmi' do
    context 'when an NMI is pending' do
      context 'and the NMI line stays asserted' do
        subject(:interrupt_lines) do
          described_class.new(status:).tap do |lines|
            lines.nmi_line = true
            lines.discard_pending_nmi
          end
        end

        let(:status) { Ruby::Nes::Cpu::Status.new }

        it 'leaves no NMI to acknowledge' do
          expect(interrupt_lines.acknowledge).to be_nil
        end
      end

      context 'and the NMI line is then released and asserted again' do
        subject(:interrupt_lines) do
          described_class.new(status:).tap do |lines|
            lines.nmi_line = true
            lines.discard_pending_nmi
            lines.nmi_line = false
            lines.nmi_line = true
          end
        end

        let(:status) { Ruby::Nes::Cpu::Status.new }

        it 'returns the NMI vector' do
          expect(interrupt_lines.acknowledge).to eq(0xFFFA)
        end
      end
    end

    context 'when the IRQ line is asserted' do
      subject(:interrupt_lines) do
        described_class.new(status:).tap do |lines|
          lines.irq_line = true
          lines.discard_pending_nmi
        end
      end

      let(:status) { Ruby::Nes::Cpu::Status.new }

      it 'keeps the IRQ' do
        expect(interrupt_lines.acknowledge).to eq(0xFFFE)
      end
    end
  end
end
