# frozen_string_literal: true

RSpec.describe Ruby::Nes::CpuBus::Disconnected do
  describe '.cpu_read' do
    it 'returns the data bus value' do
      expect(described_class.cpu_read(0x2002, 0x5A)).to eq(0x5A)
    end
  end
end
