# frozen_string_literal: true

require 'ruby/nes/frontends/base'

# The contract every frontend honours (plan 16): a frontend presents each frame, gives the buttons held on both
# controllers, says whether the emulation goes on, and takes audio samples (ignored until plan 24).
RSpec.describe Ruby::Nes::Frontends::Base do
  describe '#present' do
    subject(:frontend) { described_class.new }

    it 'raises NotImplementedError' do
      expect { frontend.present([0x0F]) }.to raise_error(NotImplementedError, /present/)
    end
  end

  describe '#button_states' do
    subject(:frontend) { described_class.new }

    it 'raises NotImplementedError' do
      expect { frontend.button_states }.to raise_error(NotImplementedError, /button_states/)
    end
  end

  describe '#running?' do
    subject(:frontend) { described_class.new }

    it 'raises NotImplementedError' do
      expect { frontend.running? }.to raise_error(NotImplementedError, /running\?/)
    end
  end

  describe '#queue_audio' do
    subject(:frontend) { described_class.new }

    it 'ignores the samples' do
      expect(frontend.queue_audio([0.5, -0.5])).to be_nil
    end
  end
end
