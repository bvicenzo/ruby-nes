# frozen_string_literal: true

# Status flags (https://www.nesdev.org/wiki/Status_flags): bits 7-0 are NV1B DIZC. Bit 5 is "always pushed as 1";
# "B is 0 when pushed by interrupts (NMI and IRQ) and 1 when pushed by instructions (BRK and PHP)"; "The two bits with
# no CPU effect are ignored when pulling flags from the stack".
RSpec.describe Ruby::Nes::Cpu::Status do
  describe '.new' do
    it 'has every flag clear' do
      expect(described_class.new.byte_pushed_by_interrupt).to eq(0x20)
    end
  end

  describe '#carry?' do
    subject(:status) { described_class.new }

    context 'when only the carry bit was restored' do
      before { status.restore(0x01) }

      it { is_expected.to be_carry }
    end

    context 'when every other bit was restored' do
      before { status.restore(0xFE) }

      it { is_expected.not_to be_carry }
    end
  end

  describe '#zero?' do
    subject(:status) { described_class.new }

    context 'when only the zero bit was restored' do
      before { status.restore(0x02) }

      it { is_expected.to be_zero }
    end

    context 'when every other bit was restored' do
      before { status.restore(0xFD) }

      it { is_expected.not_to be_zero }
    end
  end

  describe '#interrupt_disable?' do
    subject(:status) { described_class.new }

    context 'when only the interrupt disable bit was restored' do
      before { status.restore(0x04) }

      it { is_expected.to be_interrupt_disable }
    end

    context 'when every other bit was restored' do
      before { status.restore(0xFB) }

      it { is_expected.not_to be_interrupt_disable }
    end
  end

  describe '#decimal?' do
    subject(:status) { described_class.new }

    context 'when only the decimal bit was restored' do
      before { status.restore(0x08) }

      it { is_expected.to be_decimal }
    end

    context 'when every other bit was restored' do
      before { status.restore(0xF7) }

      it { is_expected.not_to be_decimal }
    end
  end

  describe '#overflow?' do
    subject(:status) { described_class.new }

    context 'when only the overflow bit was restored' do
      before { status.restore(0x40) }

      it { is_expected.to be_overflow }
    end

    context 'when every other bit was restored' do
      before { status.restore(0xBF) }

      it { is_expected.not_to be_overflow }
    end
  end

  describe '#negative?' do
    subject(:status) { described_class.new }

    context 'when only the negative bit was restored' do
      before { status.restore(0x80) }

      it { is_expected.to be_negative }
    end

    context 'when every other bit was restored' do
      before { status.restore(0x7F) }

      it { is_expected.not_to be_negative }
    end
  end

  describe '#carry=' do
    subject(:status) { described_class.new }

    context 'when every flag is clear' do
      context 'and true is assigned' do
        it 'sets only bit 0 of the pushed byte' do
          status.carry = true
          expect(status.byte_pushed_by_interrupt).to eq(0x21)
        end
      end
    end

    context 'when every flag is set' do
      before { status.restore(0xFF) }

      context 'and false is assigned' do
        it 'clears only bit 0 of the pushed byte' do
          status.carry = false
          expect(status.byte_pushed_by_interrupt).to eq(0xEE)
        end
      end
    end
  end

  describe '#zero=' do
    subject(:status) { described_class.new }

    context 'when every flag is clear' do
      context 'and true is assigned' do
        it 'sets only bit 1 of the pushed byte' do
          status.zero = true
          expect(status.byte_pushed_by_interrupt).to eq(0x22)
        end
      end
    end

    context 'when every flag is set' do
      before { status.restore(0xFF) }

      context 'and false is assigned' do
        it 'clears only bit 1 of the pushed byte' do
          status.zero = false
          expect(status.byte_pushed_by_interrupt).to eq(0xED)
        end
      end
    end
  end

  describe '#interrupt_disable=' do
    subject(:status) { described_class.new }

    context 'when every flag is clear' do
      context 'and true is assigned' do
        it 'sets only bit 2 of the pushed byte' do
          status.interrupt_disable = true
          expect(status.byte_pushed_by_interrupt).to eq(0x24)
        end
      end
    end

    context 'when every flag is set' do
      before { status.restore(0xFF) }

      context 'and false is assigned' do
        it 'clears only bit 2 of the pushed byte' do
          status.interrupt_disable = false
          expect(status.byte_pushed_by_interrupt).to eq(0xEB)
        end
      end
    end
  end

  describe '#decimal=' do
    subject(:status) { described_class.new }

    context 'when every flag is clear' do
      context 'and true is assigned' do
        it 'sets only bit 3 of the pushed byte' do
          status.decimal = true
          expect(status.byte_pushed_by_interrupt).to eq(0x28)
        end
      end
    end

    context 'when every flag is set' do
      before { status.restore(0xFF) }

      context 'and false is assigned' do
        it 'clears only bit 3 of the pushed byte' do
          status.decimal = false
          expect(status.byte_pushed_by_interrupt).to eq(0xE7)
        end
      end
    end
  end

  describe '#overflow=' do
    subject(:status) { described_class.new }

    context 'when every flag is clear' do
      context 'and true is assigned' do
        it 'sets only bit 6 of the pushed byte' do
          status.overflow = true
          expect(status.byte_pushed_by_interrupt).to eq(0x60)
        end
      end
    end

    context 'when every flag is set' do
      before { status.restore(0xFF) }

      context 'and false is assigned' do
        it 'clears only bit 6 of the pushed byte' do
          status.overflow = false
          expect(status.byte_pushed_by_interrupt).to eq(0xAF)
        end
      end
    end
  end

  describe '#negative=' do
    subject(:status) { described_class.new }

    context 'when every flag is clear' do
      context 'and true is assigned' do
        it 'sets only bit 7 of the pushed byte' do
          status.negative = true
          expect(status.byte_pushed_by_interrupt).to eq(0xA0)
        end
      end
    end

    context 'when every flag is set' do
      before { status.restore(0xFF) }

      context 'and false is assigned' do
        it 'clears only bit 7 of the pushed byte' do
          status.negative = false
          expect(status.byte_pushed_by_interrupt).to eq(0x6F)
        end
      end
    end
  end

  describe '#update_zero_and_negative' do
    subject(:status) { described_class.new }

    # Each context starts from the opposite of the expected flags, so every assertion sees a change.
    context 'when the value is $00' do
      before { status.restore(0x80) }

      it 'sets zero' do
        status.update_zero_and_negative(0x00)
        expect(status).to be_zero
      end

      it 'clears negative' do
        status.update_zero_and_negative(0x00)
        expect(status).not_to be_negative
      end
    end

    context 'when the value is $7F' do
      before { status.restore(0x82) }

      it 'clears zero' do
        status.update_zero_and_negative(0x7F)
        expect(status).not_to be_zero
      end

      it 'clears negative' do
        status.update_zero_and_negative(0x7F)
        expect(status).not_to be_negative
      end
    end

    context 'when the value is $80' do
      before { status.restore(0x02) }

      it 'clears zero' do
        status.update_zero_and_negative(0x80)
        expect(status).not_to be_zero
      end

      it 'sets negative' do
        status.update_zero_and_negative(0x80)
        expect(status).to be_negative
      end
    end

    context 'when carry, interrupt disable, decimal and overflow are set' do
      before { status.restore(0x4D) }

      it 'keeps them set' do
        status.update_zero_and_negative(0x80)
        expect(status.byte_pushed_by_interrupt).to eq(0xED)
      end
    end
  end

  describe '#byte_pushed_by_instruction' do
    subject(:status) { described_class.new }

    context 'when every flag is clear' do
      it 'is $30' do
        expect(status.byte_pushed_by_instruction).to eq(0x30)
      end
    end

    context 'when only negative, overflow, decimal and carry are set' do
      before { status.restore(0xC9) }

      it 'is $F9' do
        expect(status.byte_pushed_by_instruction).to eq(0xF9)
      end
    end

    context 'when every flag is set' do
      before { status.restore(0xFF) }

      it 'is $FF' do
        expect(status.byte_pushed_by_instruction).to eq(0xFF)
      end
    end
  end

  describe '#byte_pushed_by_interrupt' do
    subject(:status) { described_class.new }

    context 'when every flag is clear' do
      it 'is $20' do
        expect(status.byte_pushed_by_interrupt).to eq(0x20)
      end
    end

    context 'when only negative, overflow, decimal and carry are set' do
      before { status.restore(0xC9) }

      it 'is $E9' do
        expect(status.byte_pushed_by_interrupt).to eq(0xE9)
      end
    end

    context 'when every flag is set' do
      before { status.restore(0xFF) }

      it 'is $EF' do
        expect(status.byte_pushed_by_interrupt).to eq(0xEF)
      end
    end
  end

  describe '#restore' do
    subject(:status) { described_class.new }

    context 'when every flag is set' do
      before { status.restore(0xFF) }

      context 'and the byte is $00' do
        it 'clears every flag' do
          status.restore(0x00)
          expect(status.byte_pushed_by_interrupt).to eq(0x20)
        end
      end
    end

    context 'when the byte has the B bit set' do
      it 'leaves B out of the byte pushed by an interrupt' do
        status.restore(0x10)
        expect(status.byte_pushed_by_interrupt).to eq(0x20)
      end
    end
  end
end
