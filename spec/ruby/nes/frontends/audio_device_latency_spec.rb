# frozen_string_literal: true

require 'ruby/nes/frontends/audio_device_latency'

# Before raylib opens the audio device, on Linux, the latency the Pulse client asks for is shortened (plan 39): raylib's
# stream holds two sub-buffers of 800 samples, and a device asking for more at a time than fits beside one of them is
# served silence, which slowed the window paced by its audio to 53 fps. The environment is injected: here a Hash.
RSpec.describe Ruby::Nes::Frontends::AudioDeviceLatency do
  describe '.apply' do
    context 'when the system is macOS' do
      subject(:environment) { {} }

      it 'leaves the environment untouched' do
        described_class.apply(environment:, host_os: 'darwin24')

        expect(environment).to be_empty
      end
    end

    context 'when the system is Windows' do
      subject(:environment) { {} }

      it 'leaves the environment untouched' do
        described_class.apply(environment:, host_os: 'mingw32')

        expect(environment).to be_empty
      end
    end

    context 'when the system is Linux' do
      context 'but the environment already has PULSE_LATENCY_MSEC' do
        subject(:environment) { { 'PULSE_LATENCY_MSEC' => '30' } }

        it "keeps the user's value" do
          described_class.apply(environment:, host_os: 'linux-gnu')

          expect(environment).to eq('PULSE_LATENCY_MSEC' => '30')
        end
      end

      context 'and the environment has no PULSE_LATENCY_MSEC' do
        subject(:environment) { {} }

        it 'sets it to 15 milliseconds' do
          described_class.apply(environment:, host_os: 'linux-gnu')

          expect(environment).to eq('PULSE_LATENCY_MSEC' => '15')
        end
      end
    end
  end
end
