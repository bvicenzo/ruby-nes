# frozen_string_literal: true

# The CPU's two interrupt inputs (https://www.nesdev.org/wiki/CPU_interrupts). NMI is edge-sensitive: the edge detector
# notices the line going from released to asserted, and the internal signal "stays high until the NMI has been
# handled", so releasing the line does not cancel it and holding it asserted does not repeat it. IRQ is
# level-sensitive: it is taken while the line is asserted, unless I is set ("When set, IRQ interrupts are inhibited.
# NMI, BRK, and reset are not affected", https://www.nesdev.org/wiki/Status_flags). "If both an NMI and an IRQ are
# pending at the end of an instruction, the NMI will be handled". Both lines start released.
#
# The polling point (plan 12, decision 2): the CPU polls "the status of the interrupt lines at the end of the
# second-to-last cycle" of an instruction, so an NMI edge on the instruction's last cycle is taken one instruction
# later. The poll gives the cycle the next step starts on, one past the previous instruction's last cycle. The edge
# detector "polls the status of the NMI line during φ2 of each CPU cycle" and sees an edge when the input goes "from
# being high during one cycle to being low during the next", so a line asserted and released again within one cycle
# leaves no edge (plan 12, decision 2).
RSpec.describe Ruby::Nes::Cpu::InterruptLines do
  describe '#acknowledge' do
    context 'when the NMI line stays released' do
      context 'and the IRQ line stays released' do
        subject(:interrupt_lines) { described_class.new(status:) }

        let(:status) { Ruby::Nes::Cpu::Status.new }

        it 'returns nothing' do
          expect(interrupt_lines.acknowledge(10)).to be_nil
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
          expect(interrupt_lines.acknowledge(10)).to be_nil
        end
      end

      context 'and the IRQ line is asserted' do
        context 'but interrupt disable is set' do
          subject(:interrupt_lines) { described_class.new(status:).tap { |lines| lines.irq_line = true } }

          let(:status) { Ruby::Nes::Cpu::Status.new.tap { |status| status.interrupt_disable = true } }

          it 'returns nothing' do
            expect(interrupt_lines.acknowledge(10)).to be_nil
          end
        end

        context 'and interrupt disable is clear' do
          context 'and the IRQ was already acknowledged' do
            subject(:interrupt_lines) do
              described_class.new(status:).tap do |lines|
                lines.irq_line = true
                lines.acknowledge(10)
              end
            end

            let(:status) { Ruby::Nes::Cpu::Status.new }

            it 'returns the IRQ vector' do
              expect(interrupt_lines.acknowledge(17)).to eq(0xFFFE)
            end
          end

          context 'and the IRQ was not acknowledged yet' do
            subject(:interrupt_lines) { described_class.new(status:).tap { |lines| lines.irq_line = true } }

            let(:status) { Ruby::Nes::Cpu::Status.new }

            it 'returns the IRQ vector' do
              expect(interrupt_lines.acknowledge(10)).to eq(0xFFFE)
            end
          end
        end
      end
    end

    context 'when the NMI line rose from released to asserted' do
      context 'but it was released again within the same CPU cycle' do
        subject(:interrupt_lines) do
          described_class.new(status:).tap do |lines|
            lines.nmi_line_changed(true, 8)
            lines.nmi_line_changed(false, 8)
          end
        end

        let(:status) { Ruby::Nes::Cpu::Status.new }

        it 'returns nothing' do
          expect(interrupt_lines.acknowledge(10)).to be_nil
        end
      end

      context 'but the edge came on the last cycle of the previous instruction' do
        context 'and the IRQ line is released' do
          subject(:interrupt_lines) { described_class.new(status:).tap { |lines| lines.nmi_line_changed(true, 9) } }

          let(:status) { Ruby::Nes::Cpu::Status.new }

          it 'returns nothing' do
            expect(interrupt_lines.acknowledge(10)).to be_nil
          end

          it 'leaves the NMI for the next poll' do
            interrupt_lines.acknowledge(10)
            expect(interrupt_lines.acknowledge(12)).to eq(0xFFFA)
          end
        end

        context 'and the IRQ line is asserted' do
          context 'but interrupt disable is set' do
            subject(:interrupt_lines) do
              described_class.new(status:).tap do |lines|
                lines.irq_line = true
                lines.nmi_line_changed(true, 9)
              end
            end

            let(:status) { Ruby::Nes::Cpu::Status.new.tap { |status| status.interrupt_disable = true } }

            it 'returns nothing' do
              expect(interrupt_lines.acknowledge(10)).to be_nil
            end
          end

          context 'and interrupt disable is clear' do
            subject(:interrupt_lines) do
              described_class.new(status:).tap do |lines|
                lines.irq_line = true
                lines.nmi_line_changed(true, 9)
              end
            end

            let(:status) { Ruby::Nes::Cpu::Status.new }

            it 'returns the IRQ vector' do
              expect(interrupt_lines.acknowledge(10)).to eq(0xFFFE)
            end

            it 'leaves the NMI for the next poll' do
              interrupt_lines.acknowledge(10)
              expect(interrupt_lines.acknowledge(17)).to eq(0xFFFA)
            end
          end
        end
      end

      context 'and the edge came before the last cycle of the previous instruction' do
        context 'and the NMI was already acknowledged' do
          context 'and the line is asserted again without being released' do
            subject(:interrupt_lines) do
              described_class.new(status:).tap do |lines|
                lines.nmi_line_changed(true, 8)
                lines.acknowledge(10)
                lines.nmi_line_changed(true, 11)
              end
            end

            let(:status) { Ruby::Nes::Cpu::Status.new }

            it 'returns nothing' do
              expect(interrupt_lines.acknowledge(17)).to be_nil
            end
          end

          context 'and the line is released and asserted again' do
            subject(:interrupt_lines) do
              described_class.new(status:).tap do |lines|
                lines.nmi_line_changed(true, 8)
                lines.acknowledge(10)
                lines.nmi_line_changed(false, 11)
                lines.nmi_line_changed(true, 12)
              end
            end

            let(:status) { Ruby::Nes::Cpu::Status.new }

            it 'returns the NMI vector' do
              expect(interrupt_lines.acknowledge(17)).to eq(0xFFFA)
            end
          end
        end

        context 'and a second edge came on the last cycle of the previous instruction' do
          subject(:interrupt_lines) do
            described_class.new(status:).tap do |lines|
              lines.nmi_line_changed(true, 7)
              lines.nmi_line_changed(false, 8)
              lines.nmi_line_changed(true, 9)
            end
          end

          let(:status) { Ruby::Nes::Cpu::Status.new }

          it 'returns the NMI vector' do
            expect(interrupt_lines.acknowledge(10)).to eq(0xFFFA)
          end
        end

        context 'and the line was released before acknowledging' do
          subject(:interrupt_lines) do
            described_class.new(status:).tap do |lines|
              lines.nmi_line_changed(true, 8)
              lines.nmi_line_changed(false, 9)
            end
          end

          let(:status) { Ruby::Nes::Cpu::Status.new }

          it 'returns the NMI vector' do
            expect(interrupt_lines.acknowledge(10)).to eq(0xFFFA)
          end
        end

        context 'and the line is still asserted' do
          context 'and interrupt disable is set' do
            context 'and the IRQ line is released' do
              subject(:interrupt_lines) do
                described_class.new(status:).tap { |lines| lines.nmi_line_changed(true, 8) }
              end

              let(:status) { Ruby::Nes::Cpu::Status.new.tap { |status| status.interrupt_disable = true } }

              it 'returns the NMI vector' do
                expect(interrupt_lines.acknowledge(10)).to eq(0xFFFA)
              end
            end

            context 'and the IRQ line is asserted' do
              subject(:interrupt_lines) do
                described_class.new(status:).tap do |lines|
                  lines.nmi_line_changed(true, 8)
                  lines.irq_line = true
                end
              end

              let(:status) { Ruby::Nes::Cpu::Status.new.tap { |status| status.interrupt_disable = true } }

              it 'returns the NMI vector' do
                expect(interrupt_lines.acknowledge(10)).to eq(0xFFFA)
              end
            end
          end

          context 'and interrupt disable is clear' do
            context 'and the IRQ line is released' do
              subject(:interrupt_lines) do
                described_class.new(status:).tap { |lines| lines.nmi_line_changed(true, 8) }
              end

              let(:status) { Ruby::Nes::Cpu::Status.new }

              it 'returns the NMI vector' do
                expect(interrupt_lines.acknowledge(10)).to eq(0xFFFA)
              end
            end

            context 'and the IRQ line is asserted' do
              subject(:interrupt_lines) do
                described_class.new(status:).tap do |lines|
                  lines.nmi_line_changed(true, 8)
                  lines.irq_line = true
                end
              end

              let(:status) { Ruby::Nes::Cpu::Status.new }

              it 'returns the NMI vector' do
                expect(interrupt_lines.acknowledge(10)).to eq(0xFFFA)
              end
            end
          end
        end
      end
    end
  end

  describe '#pending' do
    context 'when no interrupt is due' do
      subject(:interrupt_lines) { described_class.new(status:) }

      let(:status) { Ruby::Nes::Cpu::Status.new }

      it 'returns nothing' do
        expect(interrupt_lines.pending(10)).to be_nil
      end
    end

    context 'when the NMI edge came on the last cycle of the previous instruction' do
      subject(:interrupt_lines) { described_class.new(status:).tap { |lines| lines.nmi_line_changed(true, 9) } }

      let(:status) { Ruby::Nes::Cpu::Status.new }

      it 'returns nothing' do
        expect(interrupt_lines.pending(10)).to be_nil
      end
    end

    context 'when an NMI is due' do
      subject(:interrupt_lines) { described_class.new(status:).tap { |lines| lines.nmi_line_changed(true, 8) } }

      let(:status) { Ruby::Nes::Cpu::Status.new }

      it 'returns the NMI vector' do
        expect(interrupt_lines.pending(10)).to eq(0xFFFA)
      end

      it 'leaves the NMI to acknowledge' do
        interrupt_lines.pending(10)
        expect(interrupt_lines.acknowledge(10)).to eq(0xFFFA)
      end
    end

    context 'when an IRQ is due' do
      subject(:interrupt_lines) { described_class.new(status:).tap { |lines| lines.irq_line = true } }

      let(:status) { Ruby::Nes::Cpu::Status.new }

      it 'returns the IRQ vector' do
        expect(interrupt_lines.pending(10)).to eq(0xFFFE)
      end
    end
  end

  describe '#discard_pending_nmi' do
    context 'when an NMI is pending' do
      context 'and the NMI line stays asserted' do
        subject(:interrupt_lines) do
          described_class.new(status:).tap do |lines|
            lines.nmi_line_changed(true, 0)
            lines.discard_pending_nmi
          end
        end

        let(:status) { Ruby::Nes::Cpu::Status.new }

        it 'leaves no NMI to acknowledge' do
          expect(interrupt_lines.acknowledge(10)).to be_nil
        end
      end

      context 'and the NMI line is then released and asserted again' do
        subject(:interrupt_lines) do
          described_class.new(status:).tap do |lines|
            lines.nmi_line_changed(true, 0)
            lines.discard_pending_nmi
            lines.nmi_line_changed(false, 1)
            lines.nmi_line_changed(true, 2)
          end
        end

        let(:status) { Ruby::Nes::Cpu::Status.new }

        it 'returns the NMI vector' do
          expect(interrupt_lines.acknowledge(10)).to eq(0xFFFA)
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
        expect(interrupt_lines.acknowledge(10)).to eq(0xFFFE)
      end
    end
  end
end
