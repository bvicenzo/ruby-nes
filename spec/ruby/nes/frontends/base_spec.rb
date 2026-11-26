# frozen_string_literal: true

require 'ruby/nes/frontends/base'

# The contract every frontend honours (plan 16): a frontend presents each frame, gives the buttons held on both
# controllers, says whether the emulation goes on, whether it is paused and whether the console is to be reset
# (plan 18), takes audio samples (ignored until plan 24), and releases what it opened when the run ends (plan 17). It
# may ask for a save state action, show a message and drop the audio it queued (plan 35); by default it does none. A
# window that outlives a game (plan 37) says whether the player closed it, starts over between screens and queues a
# frame of silence for a screen that makes no sound; by default it is never closed and does neither.
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

  describe '#paused?' do
    subject(:frontend) { described_class.new }

    it 'is false' do
      expect(frontend).not_to be_paused
    end
  end

  describe '#reset_requested?' do
    subject(:frontend) { described_class.new }

    it 'is false' do
      expect(frontend).not_to be_reset_requested
    end
  end

  describe '#state_action' do
    subject(:frontend) { described_class.new }

    it 'is nil' do
      expect(frontend.state_action).to be_nil
    end
  end

  describe '#notify' do
    subject(:frontend) { described_class.new }

    it 'shows nothing' do
      expect(frontend.notify('State 3 saved')).to be_nil
    end
  end

  describe '#discard_audio' do
    subject(:frontend) { described_class.new }

    it 'has nothing to drop' do
      expect(frontend.discard_audio).to be_nil
    end
  end

  describe '#queue_audio' do
    subject(:frontend) { described_class.new }

    it 'ignores the samples' do
      expect(frontend.queue_audio([0.5, -0.5])).to be_nil
    end
  end

  describe '#close' do
    subject(:frontend) { described_class.new }

    it 'has nothing to release' do
      expect(frontend.close).to be_nil
    end
  end

  describe '#closed?' do
    subject(:frontend) { described_class.new }

    it 'is false' do
      expect(frontend).not_to be_closed
    end
  end

  describe '#next_screen' do
    subject(:frontend) { described_class.new }

    it 'has nothing to start over' do
      expect(frontend.next_screen).to be_nil
    end
  end

  describe '#queue_silence' do
    subject(:frontend) { described_class.new }

    it 'has nothing to play' do
      expect(frontend.queue_silence).to be_nil
    end
  end
end
