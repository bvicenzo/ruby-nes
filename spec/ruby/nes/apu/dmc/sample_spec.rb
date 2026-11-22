# frozen_string_literal: true

# The DMC sample's address and bytes-remaining counters, the memory reader's position
# (https://www.nesdev.org/wiki/APU_DMC). $4012 gives the "Sample address = $C000 + (A * 64)" and $4013 the "Sample
# length = (L * 16) + 1 bytes"; they are reload values: "Retriggerring the sample playback reloads the value back from
# this register", so writing them leaves a playing sample alone (apu_test's 7-dmc_basics #7, "Changing $4013 shouldn't
# affect current sample length"). After each byte read the address is incremented, "If it exceeds $FFFF, it's wrapped
# around $8000", and the bytes remaining decremented; at 0 the loop flag restarts the sample, otherwise the sample-end
# interrupt is set (the flag ignores it unless enabled), and "DMC IRQ cannot be generated if loop flag (L bit) was
# set". $4015 with the DMC bit clear sets the bytes remaining to 0.
RSpec.describe Ruby::Nes::Apu::Dmc::Sample do
  describe '#restart' do
    context 'when the registers are 0' do
      subject(:sample) { described_class.new(interrupt:) }

      let(:interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag) }

      it 'starts at $C000 with 1 byte', :aggregate_failures do
        sample.restart
        expect(sample).to have_attributes(address: 0xC000, bytes_remaining: 1)
        expect(sample).to be_active
      end
    end

    context 'when the registers are $FF' do
      subject(:sample) do
        described_class.new(interrupt:).tap do |position|
          position.address_register = 0xFF
          position.length_register = 0xFF
        end
      end

      let(:interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag) }

      it 'starts at $FFC0 with 4081 bytes' do
        sample.restart
        expect(sample).to have_attributes(address: 0xFFC0, bytes_remaining: 4081)
      end
    end
  end

  describe '#address_register=' do
    context 'when a sample is playing' do
      subject(:sample) { described_class.new(interrupt:).tap(&:restart) }

      let(:interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag) }

      it 'keeps its address' do
        sample.address_register = 0x10
        expect(sample.address).to eq(0xC000)
      end
    end
  end

  describe '#length_register=' do
    context 'when a sample is playing' do
      subject(:sample) { described_class.new(interrupt:).tap(&:restart) }

      let(:interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag) }

      it 'keeps its bytes remaining' do
        sample.length_register = 0x02
        expect(sample.bytes_remaining).to eq(1)
      end
    end
  end

  describe '#advance' do
    context 'when bytes remain after it' do
      context 'and the address is below $FFFF' do
        subject(:sample) do
          described_class.new(interrupt:).tap do |position|
            position.length_register = 0x01
            position.restart
          end
        end

        let(:interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag) }

        it 'moves to the next address and counts the byte' do
          sample.advance(100)
          expect(sample).to have_attributes(address: 0xC001, bytes_remaining: 16)
        end
      end

      context 'and the address is $FFFF' do
        subject(:sample) do
          described_class.new(interrupt:).tap do |position|
            position.address_register = 0xFF
            position.length_register = 0x04
            position.restart
            63.times { |cycle| position.advance(cycle) }
          end
        end

        let(:interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag) }

        it 'wraps around to $8000' do
          sample.advance(100)
          expect(sample).to have_attributes(address: 0x8000, bytes_remaining: 1)
        end
      end
    end

    context 'when it consumes the last byte' do
      context 'and the loop flag is set' do
        subject(:sample) do
          described_class.new(interrupt:).tap do |position|
            position.loop = true
            position.restart
            position.address_register = 0x01
            position.length_register = 0x01
          end
        end

        let(:interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag, trigger: nil) }

        before { sample.advance(100) }

        it 'restarts the sample from the registers, without the interrupt', :aggregate_failures do
          expect(sample).to have_attributes(address: 0xC040, bytes_remaining: 17)
          expect(interrupt).not_to have_received(:trigger)
        end
      end

      context 'and the loop flag is clear' do
        subject(:sample) { described_class.new(interrupt:).tap(&:restart) }

        let(:interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag, trigger: nil) }

        before { sample.advance(100) }

        it 'ends the sample and triggers the interrupt on that cycle', :aggregate_failures do
          expect(sample).not_to be_active
          expect(interrupt).to have_received(:trigger).with(100)
        end
      end
    end
  end

  describe '#stop' do
    context 'when a sample is playing' do
      subject(:sample) do
        described_class.new(interrupt:).tap do |position|
          position.length_register = 0x01
          position.restart
        end
      end

      let(:interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag) }

      it 'leaves no bytes remaining', :aggregate_failures do
        sample.stop
        expect(sample.bytes_remaining).to eq(0)
        expect(sample).not_to be_active
      end
    end
  end
end
