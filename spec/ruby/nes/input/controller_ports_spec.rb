# frozen_string_literal: true

# The controller ports (https://www.nesdev.org/wiki/Controller_reading): "$4016 reads only from controller port 1, and
# $4017 reads only from controller port 2", and "both are polled from a write to $4016"
# (https://www.nesdev.org/wiki/Standard_controller). "The controller ports ($4016, $4017) affect only bits 4-0" and
# "Bits 7-5 repeat the corresponding bits from the previous read" (https://www.nesdev.org/wiki/Open_bus_behavior); the
# standard controller drives D0 only, and on the NES-001 D4-D1 read "0 if not connected"
# (https://www.nesdev.org/wiki/Controller_reading).
RSpec.describe Ruby::Nes::Input::ControllerPorts do
  describe '#cpu_read' do
    subject(:ports) { described_class.new(first: first_controller, second: second_controller) }

    context 'when the address is $4016' do
      context 'and the first controller reports 0' do
        let(:first_controller) { instance_double(Ruby::Nes::Input::Controller, read: 0) }
        let(:second_controller) { instance_double(Ruby::Nes::Input::Controller, read: 1) }

        it 'keeps bits 7-5 of the data bus and clears bits 4-0' do
          expect(ports.cpu_read(0x4016, 0xFF)).to eq(0xE0)
        end
      end

      context 'and the first controller reports 1' do
        let(:first_controller) { instance_double(Ruby::Nes::Input::Controller, read: 1) }
        let(:second_controller) { instance_double(Ruby::Nes::Input::Controller, read: 0) }

        it 'keeps bits 7-5 of the data bus and sets only bit 0' do
          expect(ports.cpu_read(0x4016, 0x5E)).to eq(0x41)
        end

        it 'leaves the second controller unread' do
          ports.cpu_read(0x4016, 0x40)
          expect(second_controller).not_to have_received(:read)
        end
      end
    end

    context 'when the address is $4017' do
      context 'and the second controller reports 0' do
        let(:first_controller) { instance_double(Ruby::Nes::Input::Controller, read: 1) }
        let(:second_controller) { instance_double(Ruby::Nes::Input::Controller, read: 0) }

        it 'keeps bits 7-5 of the data bus and clears bits 4-0' do
          expect(ports.cpu_read(0x4017, 0xFF)).to eq(0xE0)
        end
      end

      context 'and the second controller reports 1' do
        let(:first_controller) { instance_double(Ruby::Nes::Input::Controller, read: 0) }
        let(:second_controller) { instance_double(Ruby::Nes::Input::Controller, read: 1) }

        it 'keeps bits 7-5 of the data bus and sets only bit 0' do
          expect(ports.cpu_read(0x4017, 0x5E)).to eq(0x41)
        end

        it 'leaves the first controller unread' do
          ports.cpu_read(0x4017, 0x40)
          expect(first_controller).not_to have_received(:read)
        end
      end
    end
  end

  describe '#cpu_write' do
    subject(:ports) { described_class.new(first: first_controller, second: second_controller) }

    let(:first_controller) { instance_double(Ruby::Nes::Input::Controller, strobe: nil) }
    let(:second_controller) { instance_double(Ruby::Nes::Input::Controller, strobe: nil) }

    it 'strobes both controllers with the byte', :aggregate_failures do
      ports.cpu_write(0x4016, 0x01)
      expect(first_controller).to have_received(:strobe).with(0x01)
      expect(second_controller).to have_received(:strobe).with(0x01)
    end
  end
end
