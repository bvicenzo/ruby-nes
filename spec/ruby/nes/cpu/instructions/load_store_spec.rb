# frozen_string_literal: true

# Loads and stores (https://www.nesdev.org/wiki/Instruction_reference): LDA, LDX and LDY copy the byte at the effective
# address into the register and set Z ("result == 0") and N ("result bit 7"); STA, STX and STY write the register to
# the address and change no flag. The status is observed through the byte an interrupt would push (bit 5 set, B clear).
RSpec.describe Ruby::Nes::Cpu::Instructions::LoadStore do
  describe '#load_accumulator' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:) }

    let(:bus) { FlatBus.new }

    context 'when the byte at the address is $01' do
      before do
        bus.write(0x0200, 0x01)
        cpu.status.restore(0x82)
      end

      it 'loads $01' do
        cpu.load_accumulator(0x0200)
        expect(cpu.accumulator).to eq(0x01)
      end

      it 'clears zero and negative', :aggregate_failures do
        cpu.load_accumulator(0x0200)
        expect(cpu.status).not_to be_zero
        expect(cpu.status).not_to be_negative
      end
    end

    context 'when the byte at the address is $00' do
      before do
        bus.write(0x0200, 0x00)
        cpu.status.restore(0x80)
      end

      it 'sets zero and clears negative', :aggregate_failures do
        cpu.load_accumulator(0x0200)
        expect(cpu.status).to be_zero
        expect(cpu.status).not_to be_negative
      end
    end

    context 'when the byte at the address is $80' do
      before do
        bus.write(0x0200, 0x80)
        cpu.status.restore(0x02)
      end

      it 'sets negative and clears zero', :aggregate_failures do
        cpu.load_accumulator(0x0200)
        expect(cpu.status).to be_negative
        expect(cpu.status).not_to be_zero
      end
    end

    context 'when carry, interrupt disable, decimal and overflow are set' do
      before do
        bus.write(0x0200, 0x01)
        cpu.status.restore(0x4D)
      end

      it 'leaves them set' do
        cpu.load_accumulator(0x0200)
        expect(cpu.status.byte_pushed_by_interrupt).to eq(0x6D)
      end
    end
  end

  describe '#load_index_x' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:) }

    let(:bus) { FlatBus.new }

    context 'when the byte at the address is $01' do
      before do
        bus.write(0x0200, 0x01)
        cpu.status.restore(0x82)
      end

      it 'loads $01' do
        cpu.load_index_x(0x0200)
        expect(cpu.index_x).to eq(0x01)
      end

      it 'clears zero and negative', :aggregate_failures do
        cpu.load_index_x(0x0200)
        expect(cpu.status).not_to be_zero
        expect(cpu.status).not_to be_negative
      end
    end

    context 'when the byte at the address is $00' do
      before do
        bus.write(0x0200, 0x00)
        cpu.status.restore(0x80)
      end

      it 'sets zero and clears negative', :aggregate_failures do
        cpu.load_index_x(0x0200)
        expect(cpu.status).to be_zero
        expect(cpu.status).not_to be_negative
      end
    end

    context 'when the byte at the address is $80' do
      before do
        bus.write(0x0200, 0x80)
        cpu.status.restore(0x02)
      end

      it 'sets negative and clears zero', :aggregate_failures do
        cpu.load_index_x(0x0200)
        expect(cpu.status).to be_negative
        expect(cpu.status).not_to be_zero
      end
    end

    context 'when carry, interrupt disable, decimal and overflow are set' do
      before do
        bus.write(0x0200, 0x01)
        cpu.status.restore(0x4D)
      end

      it 'leaves them set' do
        cpu.load_index_x(0x0200)
        expect(cpu.status.byte_pushed_by_interrupt).to eq(0x6D)
      end
    end
  end

  describe '#load_index_y' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:) }

    let(:bus) { FlatBus.new }

    context 'when the byte at the address is $01' do
      before do
        bus.write(0x0200, 0x01)
        cpu.status.restore(0x82)
      end

      it 'loads $01' do
        cpu.load_index_y(0x0200)
        expect(cpu.index_y).to eq(0x01)
      end

      it 'clears zero and negative', :aggregate_failures do
        cpu.load_index_y(0x0200)
        expect(cpu.status).not_to be_zero
        expect(cpu.status).not_to be_negative
      end
    end

    context 'when the byte at the address is $00' do
      before do
        bus.write(0x0200, 0x00)
        cpu.status.restore(0x80)
      end

      it 'sets zero and clears negative', :aggregate_failures do
        cpu.load_index_y(0x0200)
        expect(cpu.status).to be_zero
        expect(cpu.status).not_to be_negative
      end
    end

    context 'when the byte at the address is $80' do
      before do
        bus.write(0x0200, 0x80)
        cpu.status.restore(0x02)
      end

      it 'sets negative and clears zero', :aggregate_failures do
        cpu.load_index_y(0x0200)
        expect(cpu.status).to be_negative
        expect(cpu.status).not_to be_zero
      end
    end

    context 'when carry, interrupt disable, decimal and overflow are set' do
      before do
        bus.write(0x0200, 0x01)
        cpu.status.restore(0x4D)
      end

      it 'leaves them set' do
        cpu.load_index_y(0x0200)
        expect(cpu.status.byte_pushed_by_interrupt).to eq(0x6D)
      end
    end
  end

  describe '#store_accumulator' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:, accumulator:) }

    let(:bus) { FlatBus.new }

    context 'when the register holds $00' do
      let(:accumulator) { 0x00 }

      before { bus.write(0x0200, 0xFF) }

      it 'writes $00 at the address' do
        cpu.store_accumulator(0x0200)
        expect(bus.read(0x0200)).to eq(0x00)
      end

      it 'leaves the status unchanged' do
        cpu.store_accumulator(0x0200)
        expect(cpu.status.byte_pushed_by_interrupt).to eq(0x20)
      end
    end

    context 'when the register holds $80' do
      let(:accumulator) { 0x80 }

      it 'leaves the status unchanged' do
        cpu.store_accumulator(0x0200)
        expect(cpu.status.byte_pushed_by_interrupt).to eq(0x20)
      end
    end
  end

  describe '#store_index_x' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:, index_x:) }

    let(:bus) { FlatBus.new }

    context 'when the register holds $00' do
      let(:index_x) { 0x00 }

      before { bus.write(0x0200, 0xFF) }

      it 'writes $00 at the address' do
        cpu.store_index_x(0x0200)
        expect(bus.read(0x0200)).to eq(0x00)
      end

      it 'leaves the status unchanged' do
        cpu.store_index_x(0x0200)
        expect(cpu.status.byte_pushed_by_interrupt).to eq(0x20)
      end
    end

    context 'when the register holds $80' do
      let(:index_x) { 0x80 }

      it 'leaves the status unchanged' do
        cpu.store_index_x(0x0200)
        expect(cpu.status.byte_pushed_by_interrupt).to eq(0x20)
      end
    end
  end

  describe '#store_index_y' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:, index_y:) }

    let(:bus) { FlatBus.new }

    context 'when the register holds $00' do
      let(:index_y) { 0x00 }

      before { bus.write(0x0200, 0xFF) }

      it 'writes $00 at the address' do
        cpu.store_index_y(0x0200)
        expect(bus.read(0x0200)).to eq(0x00)
      end

      it 'leaves the status unchanged' do
        cpu.store_index_y(0x0200)
        expect(cpu.status.byte_pushed_by_interrupt).to eq(0x20)
      end
    end

    context 'when the register holds $80' do
      let(:index_y) { 0x80 }

      it 'leaves the status unchanged' do
        cpu.store_index_y(0x0200)
        expect(cpu.status.byte_pushed_by_interrupt).to eq(0x20)
      end
    end
  end
end
