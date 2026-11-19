# frozen_string_literal: true

# blargg's 2005 ROMs (sprite_hit_tests_2005.10.05, sprite_overflow_tests) report "on screen and by beeping"; their
# source (validation.a, runtime_rom.a in https://github.com/christopherpow/nes-test-roms) keeps the result in
# `result = $f8`, 1 for passed and the failing test's number otherwise, and ends in `exit: jmp exit`, in PRG ROM
# ($8000-$FFFF, https://www.nesdev.org/wiki/CPU_memory_map). The programs load at $8000, where the console's reset
# leaves PC.
RSpec.describe Blargg::LegacyReport do
  describe '#state' do
    subject(:report) { described_class.new(console) }

    let(:console) { Ruby::Nes::Console.new(cartridge) }

    context 'when PC is outside PRG ROM' do
      # LDA #$4C / STA $0300 / LDA #$00 / STA $0301 / LDA #$03 / STA $0302 / JMP $0300: a JMP to itself in RAM.
      let(:cartridge) do
        Cartridges.with_program(
          [0xA9, 0x4C, 0x8D, 0x00, 0x03, 0xA9, 0x00, 0x8D, 0x01, 0x03, 0xA9, 0x03, 0x8D, 0x02, 0x03, 0x4C, 0x00, 0x03]
        )
      end

      before { console.run_frame }

      it 'is running' do
        expect(report.state).to eq(:running)
      end
    end

    context 'when PC is in PRG ROM' do
      context 'but the instruction there is not an absolute JMP' do
        # NOP.
        let(:cartridge) { Cartridges.with_program([0xEA]) }

        it 'is running' do
          expect(report.state).to eq(:running)
        end
      end

      context 'but it is an absolute JMP elsewhere' do
        # JMP $8003.
        let(:cartridge) { Cartridges.with_program([0x4C, 0x03, 0x80]) }

        it 'is running' do
          expect(report.state).to eq(:running)
        end
      end

      context 'and it is an absolute JMP to itself' do
        # JMP $8000.
        let(:cartridge) { Cartridges.with_program([0x4C, 0x00, 0x80]) }

        it 'is finished' do
          expect(report.state).to eq(:finished)
        end
      end
    end
  end

  describe '#code' do
    subject(:report) { described_class.new(console) }

    # LDA #$07 / STA $F8.
    let(:console) { Ruby::Nes::Console.new(Cartridges.with_program([0xA9, 0x07, 0x85, 0xF8])) }

    before do
      console.step
      console.step
    end

    it 'is the byte at $F8' do
      expect(report.code).to eq(0x07)
    end
  end

  describe '#text' do
    subject(:report) { described_class.new(console) }

    let(:console) { Ruby::Nes::Console.new(Cartridges.with_program([0xEA])) }

    it 'is empty' do
      expect(report.text).to eq('')
    end
  end
end
