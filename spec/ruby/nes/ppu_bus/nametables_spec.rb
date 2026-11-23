# frozen_string_literal: true

# Mirroring arrangements (https://www.nesdev.org/wiki/Mirroring), named as that page and the iNES header name them:
# horizontal shares $2000 with $2400 and $2800 with $2C00 ("connect PPU A11 to CIRAM A10"); vertical shares $2000 with
# $2800 and $2400 with $2C00 ("connect PPU A10 to CIRAM A10"); single-screen puts "lower bank or upper bank" in all four;
# four-screen gives "4 unique nametables". "$3000-3EFF is usually a mirror of the 2kB region from $2000-2EFF"
# (https://www.nesdev.org/wiki/PPU_memory_map). The board tells the nametables its mirroring whenever it changes, once
# they gave themselves to it (plan 30, decision 3).
RSpec.describe Ruby::Nes::PpuBus::Nametables do
  describe '.new' do
    let(:mapper) { instance_double(Ruby::Nes::Mappers::Nrom, mirroring: :horizontal, :nametables= => nil) }

    it 'gives itself to the board, which tells it its mirroring from then on' do
      nametables = described_class.new(mapper:)
      expect(mapper).to have_received(:nametables=).with(nametables)
    end
  end

  describe '#read' do
    subject(:nametables) { described_class.new(mapper:) }

    context 'when nothing was written' do
      let(:mapper) { instance_double(Ruby::Nes::Mappers::Nrom, mirroring: :horizontal, :nametables= => nil) }

      it 'returns 0' do
        expect(nametables.read(0x2123)).to eq(0x00)
      end
    end

    context 'when the mirroring is horizontal' do
      let(:mapper) { instance_double(Ruby::Nes::Mappers::Nrom, mirroring: :horizontal, :nametables= => nil) }

      before do
        nametables.write(0x2005, 0x11)
        nametables.write(0x2805, 0x22)
      end

      it 'reads $2400 as $2000 and $2C00 as $2800', :aggregate_failures do
        expect(nametables.read(0x2405)).to eq(0x11)
        expect(nametables.read(0x2C05)).to eq(0x22)
      end

      it 'reads $2000 and $2800 apart' do
        expect(nametables.read(0x2005)).to eq(0x11)
      end
    end

    context 'when the mirroring is vertical' do
      let(:mapper) { instance_double(Ruby::Nes::Mappers::Nrom, mirroring: :vertical, :nametables= => nil) }

      before do
        nametables.write(0x2005, 0x11)
        nametables.write(0x2405, 0x22)
      end

      it 'reads $2800 as $2000 and $2C00 as $2400', :aggregate_failures do
        expect(nametables.read(0x2805)).to eq(0x11)
        expect(nametables.read(0x2C05)).to eq(0x22)
      end

      it 'reads $2000 and $2400 apart' do
        expect(nametables.read(0x2005)).to eq(0x11)
      end
    end

    context 'when the mirroring is single-screen lower' do
      let(:mapper) { instance_double(Ruby::Nes::Mappers::Nrom, mirroring: :single_screen_lower, :nametables= => nil) }

      before { nametables.write(0x2C05, 0x33) }

      it 'reads the four nametables as one', :aggregate_failures do
        expect(nametables.read(0x2005)).to eq(0x33)
        expect(nametables.read(0x2405)).to eq(0x33)
        expect(nametables.read(0x2805)).to eq(0x33)
      end
    end

    context 'when the mirroring is single-screen upper' do
      let(:mapper) { instance_double(Ruby::Nes::Mappers::Nrom, mirroring: :single_screen_upper, :nametables= => nil) }

      before { nametables.write(0x2005, 0x44) }

      it 'reads the four nametables as one', :aggregate_failures do
        expect(nametables.read(0x2405)).to eq(0x44)
        expect(nametables.read(0x2805)).to eq(0x44)
        expect(nametables.read(0x2C05)).to eq(0x44)
      end
    end

    context 'when the mirroring is four-screen' do
      let(:mapper) { instance_double(Ruby::Nes::Mappers::Nrom, mirroring: :four_screen, :nametables= => nil) }

      before do
        nametables.write(0x2005, 0x11)
        nametables.write(0x2405, 0x22)
        nametables.write(0x2805, 0x33)
        nametables.write(0x2C05, 0x44)
      end

      it 'reads the four nametables apart', :aggregate_failures do
        expect(nametables.read(0x2005)).to eq(0x11)
        expect(nametables.read(0x2405)).to eq(0x22)
        expect(nametables.read(0x2805)).to eq(0x33)
        expect(nametables.read(0x2C05)).to eq(0x44)
      end
    end

    context 'when the board changes the mirroring between accesses' do
      let(:mapper) { instance_double(Ruby::Nes::Mappers::Nrom, mirroring: :horizontal, :nametables= => nil) }

      context 'and it goes from horizontal to single-screen lower' do
        before do
          nametables.write(0x2005, 0x11)
          nametables.write(0x2805, 0x22)
          nametables.mirroring_changed(:single_screen_lower)
        end

        it 'reads the page horizontal mirroring gave $2000' do
          expect(nametables.read(0x2C05)).to eq(0x11)
        end
      end

      context 'and it goes from horizontal to single-screen upper' do
        before do
          nametables.write(0x2005, 0x11)
          nametables.write(0x2805, 0x22)
          nametables.mirroring_changed(:single_screen_upper)
        end

        it 'reads the page horizontal mirroring gave $2800' do
          expect(nametables.read(0x2005)).to eq(0x22)
        end
      end
    end

    context 'when the address is in $3000-$3EFF' do
      let(:mapper) { instance_double(Ruby::Nes::Mappers::Nrom, mirroring: :four_screen, :nametables= => nil) }

      context 'and it is $3000' do
        before { nametables.write(0x2000, 0x55) }

        it 'returns the byte written at $2000' do
          expect(nametables.read(0x3000)).to eq(0x55)
        end
      end

      context 'and it is $3EFF' do
        before { nametables.write(0x2EFF, 0x66) }

        it 'returns the byte written at $2EFF' do
          expect(nametables.read(0x3EFF)).to eq(0x66)
        end
      end
    end
  end

  describe '#write' do
    subject(:nametables) { described_class.new(mapper:) }

    context 'when the mirroring is horizontal' do
      let(:mapper) { instance_double(Ruby::Nes::Mappers::Nrom, mirroring: :horizontal, :nametables= => nil) }

      before do
        nametables.write(0x2405, 0x11)
        nametables.write(0x2C05, 0x22)
      end

      it 'is read at $2000 when written at $2400 and at $2800 when written at $2C00', :aggregate_failures do
        expect(nametables.read(0x2005)).to eq(0x11)
        expect(nametables.read(0x2805)).to eq(0x22)
      end
    end

    context 'when the mirroring is vertical' do
      let(:mapper) { instance_double(Ruby::Nes::Mappers::Nrom, mirroring: :vertical, :nametables= => nil) }

      before do
        nametables.write(0x2805, 0x11)
        nametables.write(0x2C05, 0x22)
      end

      it 'is read at $2000 when written at $2800 and at $2400 when written at $2C00', :aggregate_failures do
        expect(nametables.read(0x2005)).to eq(0x11)
        expect(nametables.read(0x2405)).to eq(0x22)
      end
    end

    context 'when the address is in $3000-$3EFF' do
      let(:mapper) { instance_double(Ruby::Nes::Mappers::Nrom, mirroring: :four_screen, :nametables= => nil) }

      context 'and it is $3000' do
        before { nametables.write(0x3000, 0x55) }

        it 'is read at $2000' do
          expect(nametables.read(0x2000)).to eq(0x55)
        end
      end

      context 'and it is $3EFF' do
        before { nametables.write(0x3EFF, 0x66) }

        it 'is read at $2EFF' do
          expect(nametables.read(0x2EFF)).to eq(0x66)
        end
      end
    end
  end
end
