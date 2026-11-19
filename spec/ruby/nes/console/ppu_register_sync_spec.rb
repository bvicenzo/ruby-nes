# frozen_string_literal: true

# Register-access synchronisation (plan 12, decision 1): Cpu#step charges an instruction's base cycles before running
# it, so during the instruction `cpu.cycles` is the cycle it ends on, and a non-read-modify-write instruction makes its
# data access on its last cycle (https://www.nesdev.org/6502_cpu.txt). Before each access to $2000-$3FFF the PPU
# catches up to the start of that cycle.
RSpec.describe Ruby::Nes::Console::PpuRegisterSync do
  describe '#cpu_read' do
    subject(:register_sync) { described_class.new(ppu:, cpu:) }

    let(:ppu) { instance_double(Ruby::Nes::Ppu, catch_up: nil, cpu_read: 0x80) }
    let(:cpu) { instance_double(Ruby::Nes::Cpu, cycles: 14) }

    it "catches the PPU up to the start of the instruction's last cycle, then reads", :aggregate_failures do
      register_sync.cpu_read(0x2002, 0x20)
      expect(ppu).to have_received(:catch_up).with(13).ordered
      expect(ppu).to have_received(:cpu_read).with(0x2002, 0x20).ordered
    end

    it "returns the PPU's answer" do
      expect(register_sync.cpu_read(0x2002, 0x20)).to eq(0x80)
    end
  end

  describe '#cpu_write' do
    subject(:register_sync) { described_class.new(ppu:, cpu:) }

    let(:ppu) { instance_double(Ruby::Nes::Ppu, catch_up: nil, cpu_write: nil) }
    let(:cpu) { instance_double(Ruby::Nes::Cpu, cycles: 14) }

    it "catches the PPU up to the start of the instruction's last cycle, then writes", :aggregate_failures do
      register_sync.cpu_write(0x2000, 0x80)
      expect(ppu).to have_received(:catch_up).with(13).ordered
      expect(ppu).to have_received(:cpu_write).with(0x2000, 0x80).ordered
    end
  end
end
