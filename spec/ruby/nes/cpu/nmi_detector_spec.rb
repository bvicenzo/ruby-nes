# frozen_string_literal: true

# The NMI edge detector (https://www.nesdev.org/wiki/CPU_interrupts): it "polls the status of the NMI line during φ2 of
# each CPU cycle" and notices the line going "from being high during one cycle to being low during the next"; the
# internal signal "stays high until the NMI has been handled", so releasing the line does not cancel it and holding it
# asserted does not repeat it. Each change carries the first CPU cycle whose φ2 sample sees it, so a line asserted and
# released again within one cycle leaves no edge (plan 12, decision 2). A poll sees an edge that came before its poll
# cycle.
RSpec.describe Ruby::Nes::Cpu::NmiDetector do
  describe '#pending_before?' do
    context 'when the line never rose' do
      subject(:detector) { described_class.new }

      it 'sees nothing pending' do
        expect(detector).not_to be_pending_before(10)
      end
    end

    context 'when the line rose' do
      context 'but it was released again within the same cycle' do
        subject(:detector) do
          described_class.new.tap do |nmi|
            nmi.line_changed(true, 8)
            nmi.line_changed(false, 8)
          end
        end

        it 'sees nothing pending' do
          expect(detector).not_to be_pending_before(10)
        end
      end

      context 'and it stayed asserted past the cycle it rose in' do
        context 'but the edge came on the poll cycle' do
          subject(:detector) { described_class.new.tap { |nmi| nmi.line_changed(true, 9) } }

          it 'sees nothing pending' do
            expect(detector).not_to be_pending_before(9)
          end
        end

        context 'and the edge came before the poll cycle' do
          context 'but the NMI was cleared' do
            context 'and the line stays asserted' do
              subject(:detector) do
                described_class.new.tap do |nmi|
                  nmi.line_changed(true, 8)
                  nmi.clear_pending
                  nmi.line_changed(true, 11)
                end
              end

              it 'sees nothing pending' do
                expect(detector).not_to be_pending_before(16)
              end
            end

            context 'and the line was released and rose again' do
              subject(:detector) do
                described_class.new.tap do |nmi|
                  nmi.line_changed(true, 8)
                  nmi.clear_pending
                  nmi.line_changed(false, 11)
                  nmi.line_changed(true, 12)
                end
              end

              it 'sees it pending' do
                expect(detector).to be_pending_before(16)
              end
            end
          end

          context 'and the NMI was not cleared' do
            context 'and the line was released since' do
              subject(:detector) do
                described_class.new.tap do |nmi|
                  nmi.line_changed(true, 8)
                  nmi.line_changed(false, 9)
                end
              end

              it 'sees it pending' do
                expect(detector).to be_pending_before(9)
              end
            end

            context 'and the line was released and rose again on the poll cycle' do
              subject(:detector) do
                described_class.new.tap do |nmi|
                  nmi.line_changed(true, 7)
                  nmi.line_changed(false, 8)
                  nmi.line_changed(true, 9)
                end
              end

              it 'sees it pending' do
                expect(detector).to be_pending_before(9)
              end
            end

            context 'and the line is still asserted' do
              subject(:detector) { described_class.new.tap { |nmi| nmi.line_changed(true, 8) } }

              it 'sees it pending' do
                expect(detector).to be_pending_before(9)
              end
            end
          end
        end
      end
    end
  end
end
