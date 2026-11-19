# frozen_string_literal: true

# "The PPU pulls /NMI low if and only if both vblank_flag and NMI_output are true" (https://www.nesdev.org/wiki/NMI).
# "Changing NMI enable from 0 to 1 while the vblank flag in PPUSTATUS is 1 will immediately trigger an NMI"; reading
# PPUSTATUS clears the VBlank flag (https://www.nesdev.org/wiki/PPU_registers). The flag is clear at power by
# convention (plan 12, decision 8); the /NMI level is told to the output only when it changes (plan 12, the
# `Ppu::VerticalBlank` task).
RSpec.describe Ruby::Nes::Ppu::VerticalBlank do
  describe '.new' do
    let(:nmi_output) { instance_double(Ruby::Nes::Ppu) }

    it 'starts with the flag clear and NMI disabled' do
      vertical_blank = described_class.new(nmi_output:)
      expect(vertical_blank).to have_attributes(flag_set?: false, nmi_enabled?: false)
    end
  end

  describe '#vertical_blank_started' do
    subject(:vertical_blank) { described_class.new(nmi_output:, flag_set:, nmi_enabled:) }

    let(:nmi_output) { instance_double(Ruby::Nes::Ppu, nmi_output_changed: nil) }

    context 'when the flag is already set' do
      let(:flag_set) { true }

      context 'and NMI is disabled' do
        let(:nmi_enabled) { false }

        before { vertical_blank.vertical_blank_started }

        it 'keeps the flag set' do
          expect(vertical_blank).to be_flag_set
        end

        it 'tells the output nothing' do
          expect(nmi_output).not_to have_received(:nmi_output_changed)
        end
      end

      context 'and NMI is enabled' do
        let(:nmi_enabled) { true }

        before { vertical_blank.vertical_blank_started }

        it 'keeps the flag set' do
          expect(vertical_blank).to be_flag_set
        end

        it 'tells the output nothing' do
          expect(nmi_output).not_to have_received(:nmi_output_changed)
        end
      end
    end

    context 'when the flag is clear' do
      let(:flag_set) { false }

      context 'and NMI is disabled' do
        let(:nmi_enabled) { false }

        it 'sets the flag' do
          expect { vertical_blank.vertical_blank_started }.to change(vertical_blank, :flag_set?).from(false).to(true)
        end

        it 'tells the output nothing' do
          vertical_blank.vertical_blank_started
          expect(nmi_output).not_to have_received(:nmi_output_changed)
        end
      end

      context 'and NMI is enabled' do
        let(:nmi_enabled) { true }

        it 'sets the flag' do
          expect { vertical_blank.vertical_blank_started }.to change(vertical_blank, :flag_set?).from(false).to(true)
        end

        it 'asserts the output' do
          vertical_blank.vertical_blank_started
          expect(nmi_output).to have_received(:nmi_output_changed).with(true).once
        end
      end
    end
  end

  describe '#vertical_blank_ended' do
    subject(:vertical_blank) { described_class.new(nmi_output:, flag_set:, nmi_enabled:) }

    let(:nmi_output) { instance_double(Ruby::Nes::Ppu, nmi_output_changed: nil) }

    context 'when the flag is clear' do
      let(:flag_set) { false }

      context 'and NMI is disabled' do
        let(:nmi_enabled) { false }

        it 'tells the output nothing' do
          vertical_blank.vertical_blank_ended
          expect(nmi_output).not_to have_received(:nmi_output_changed)
        end
      end

      context 'and NMI is enabled' do
        let(:nmi_enabled) { true }

        it 'tells the output nothing' do
          vertical_blank.vertical_blank_ended
          expect(nmi_output).not_to have_received(:nmi_output_changed)
        end
      end
    end

    context 'when the flag is set' do
      let(:flag_set) { true }

      context 'and NMI is disabled' do
        let(:nmi_enabled) { false }

        it 'clears the flag' do
          expect { vertical_blank.vertical_blank_ended }.to change(vertical_blank, :flag_set?).from(true).to(false)
        end

        it 'tells the output nothing' do
          vertical_blank.vertical_blank_ended
          expect(nmi_output).not_to have_received(:nmi_output_changed)
        end
      end

      context 'and NMI is enabled' do
        let(:nmi_enabled) { true }

        it 'clears the flag' do
          expect { vertical_blank.vertical_blank_ended }.to change(vertical_blank, :flag_set?).from(true).to(false)
        end

        it 'releases the output' do
          vertical_blank.vertical_blank_ended
          expect(nmi_output).to have_received(:nmi_output_changed).with(false).once
        end
      end
    end
  end

  describe '#nmi_enabled=' do
    subject(:vertical_blank) { described_class.new(nmi_output:, flag_set:, nmi_enabled:) }

    let(:nmi_output) { instance_double(Ruby::Nes::Ppu, nmi_output_changed: nil) }

    context 'when NMI is disabled' do
      let(:nmi_enabled) { false }

      context 'and it is disabled again' do
        context 'and the flag is clear' do
          let(:flag_set) { false }

          it 'tells the output nothing' do
            vertical_blank.nmi_enabled = false
            expect(nmi_output).not_to have_received(:nmi_output_changed)
          end
        end

        context 'and the flag is set' do
          let(:flag_set) { true }

          it 'tells the output nothing' do
            vertical_blank.nmi_enabled = false
            expect(nmi_output).not_to have_received(:nmi_output_changed)
          end
        end
      end

      context 'and it is enabled' do
        context 'but the flag is clear' do
          let(:flag_set) { false }

          it 'tells the output nothing' do
            vertical_blank.nmi_enabled = true
            expect(nmi_output).not_to have_received(:nmi_output_changed)
          end
        end

        context 'and the flag is set' do
          let(:flag_set) { true }

          it 'asserts the output' do
            vertical_blank.nmi_enabled = true
            expect(nmi_output).to have_received(:nmi_output_changed).with(true).once
          end
        end
      end
    end

    context 'when NMI is enabled' do
      let(:nmi_enabled) { true }

      context 'and it is enabled again' do
        context 'and the flag is clear' do
          let(:flag_set) { false }

          it 'tells the output nothing' do
            vertical_blank.nmi_enabled = true
            expect(nmi_output).not_to have_received(:nmi_output_changed)
          end
        end

        context 'and the flag is set' do
          let(:flag_set) { true }

          it 'tells the output nothing' do
            vertical_blank.nmi_enabled = true
            expect(nmi_output).not_to have_received(:nmi_output_changed)
          end
        end
      end

      context 'and it is disabled' do
        context 'but the flag is clear' do
          let(:flag_set) { false }

          it 'tells the output nothing' do
            vertical_blank.nmi_enabled = false
            expect(nmi_output).not_to have_received(:nmi_output_changed)
          end
        end

        context 'and the flag is set' do
          let(:flag_set) { true }

          it 'releases the output' do
            vertical_blank.nmi_enabled = false
            expect(nmi_output).to have_received(:nmi_output_changed).with(false).once
          end
        end
      end
    end
  end

  describe '#read' do
    subject(:vertical_blank) { described_class.new(nmi_output:, flag_set:, nmi_enabled:) }

    let(:nmi_output) { instance_double(Ruby::Nes::Ppu, nmi_output_changed: nil) }

    context 'when the flag is clear' do
      let(:flag_set) { false }

      context 'and NMI is disabled' do
        let(:nmi_enabled) { false }

        it 'returns false' do
          expect(vertical_blank.read).to be(false)
        end

        it 'tells the output nothing' do
          vertical_blank.read
          expect(nmi_output).not_to have_received(:nmi_output_changed)
        end
      end

      context 'and NMI is enabled' do
        let(:nmi_enabled) { true }

        it 'returns false' do
          expect(vertical_blank.read).to be(false)
        end

        it 'tells the output nothing' do
          vertical_blank.read
          expect(nmi_output).not_to have_received(:nmi_output_changed)
        end
      end
    end

    context 'when the flag is set' do
      let(:flag_set) { true }

      context 'and NMI is disabled' do
        let(:nmi_enabled) { false }

        it 'returns true' do
          expect(vertical_blank.read).to be(true)
        end

        it 'clears the flag' do
          expect { vertical_blank.read }.to change(vertical_blank, :flag_set?).from(true).to(false)
        end

        it 'tells the output nothing' do
          vertical_blank.read
          expect(nmi_output).not_to have_received(:nmi_output_changed)
        end
      end

      context 'and NMI is enabled' do
        let(:nmi_enabled) { true }

        it 'returns true' do
          expect(vertical_blank.read).to be(true)
        end

        it 'clears the flag' do
          expect { vertical_blank.read }.to change(vertical_blank, :flag_set?).from(true).to(false)
        end

        it 'releases the output' do
          vertical_blank.read
          expect(nmi_output).to have_received(:nmi_output_changed).with(false).once
        end
      end
    end
  end
end
