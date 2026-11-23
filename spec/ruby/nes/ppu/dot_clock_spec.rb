# frozen_string_literal: true

# The PPU's elapsed dots, a count that never wraps (plan 21, decision 2), shared by the Ppu, which counts the dots it
# enters, and the renderer, which moves it to each dot of a range before that dot's fetches (plan 28, decision 5).
RSpec.describe Ruby::Nes::Ppu::DotClock do
  describe '.new' do
    it 'starts at 0 dots' do
      expect(described_class.new.elapsed_dots).to eq(0)
    end
  end

  describe '#tick' do
    subject(:clock) { described_class.new }

    it 'counts one more dot' do
      expect { clock.tick }.to change(clock, :elapsed_dots).from(0).to(1)
    end
  end

  describe '#elapsed_dots=' do
    subject(:clock) { described_class.new }

    it 'stands on the count given' do
      expect { clock.elapsed_dots = 300 }.to change(clock, :elapsed_dots).from(0).to(300)
    end
  end
end
