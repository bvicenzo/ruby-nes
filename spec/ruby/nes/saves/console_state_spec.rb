# frozen_string_literal: true

require 'zlib'
require 'ruby/nes/saves'

# A save state's bytes (plan 35, decisions 1 and 2): a header and the console's snapshot, compressed with zlib. The
# header holds magic bytes, the format's version, the SHA-256 of the ROM, the sample rate the console mixes at (0 with
# no sound: a console with sound holds more objects) and a fingerprint of the code: the console's shape
# (Saves::Shape) with the core's constants (Saves::ConstantsDigest). A state is restored only into a console of the
# same ROM, sound and code; any other, or a damaged one, is refused with the reason, and the console is left as it was.
# A state with no ROM inside is small.
RSpec.describe Ruby::Nes::Saves::ConsoleState do
  describe '#encode' do
    subject(:state) { described_class.new(console) }

    # 32 KiB of PRG ROM and 8 KiB of CHR ROM of seeded random bytes, which zlib cannot shrink: the console is built,
    # never run.
    let(:cartridge) do
      Cartridges.build(prg_rom: Random.new(35).bytes(32_768).bytes, chr_rom: Random.new(36).bytes(8_192).bytes)
    end
    let(:console) { Ruby::Nes::Console.new(cartridge) }

    it 'leaves the ROM out' do
      expect(state.encode.bytesize).to be < 16_384
    end
  end

  # The key of the ROM browser's preview cache (plan 37, decision 2).
  describe '#rom_digest' do
    subject(:state) { described_class.new(console) }

    context 'when the cartridge has CHR ROM' do
      # 16 KiB of NOP and 8 KiB of zeros.
      let(:console) { Ruby::Nes::Console.new(Cartridges.build) }

      it 'is the SHA-256 of its PRG ROM then its CHR ROM, in hexadecimal' do
        expect(state.rom_digest).to eq('b870f6206319c9cdf988b1e9846527a10644011203edf2b0fb1d45568d79b6db')
      end
    end

    context 'when the cartridge has CHR RAM' do
      # 16 KiB of NOP.
      let(:console) { Ruby::Nes::Console.new(Cartridges.build(chr_rom: [])) }

      it 'is the SHA-256 of its PRG ROM alone' do
        expect(state.rom_digest).to eq('78f2530731cd8b40e507d5ddd553996979d53aa1ab0de31fca1cfbfb43fb021f')
      end
    end
  end

  describe '#restore' do
    subject(:state) { described_class.new(console) }

    # JMP $8000, forever, without sound.
    let(:console) { Ruby::Nes::Console.new(Cartridges.with_program([0x4C, 0x00, 0x80])) }

    context 'when the bytes do not start as a state' do
      context 'and they are empty' do
        it 'raises InvalidState, leaving the console as it was', :aggregate_failures do
          cycles = console.cpu.cycles

          expect { state.restore('') }.to raise_error(Ruby::Nes::Saves::InvalidState, 'not a ruby-nes state')
          expect(console.cpu.cycles).to eq(cycles)
        end
      end

      context 'and they are another file' do
        it 'raises InvalidState, leaving the console as it was', :aggregate_failures do
          cycles = console.cpu.cycles

          expect { state.restore("\x89PNG\r\n\x1A\n".b * 40) }
            .to raise_error(Ruby::Nes::Saves::InvalidState, 'not a ruby-nes state')
          expect(console.cpu.cycles).to eq(cycles)
        end
      end
    end

    context 'when the bytes start as a state' do
      context 'but the format is another' do
        let(:other_format) { "#{described_class::MAGIC}\x02#{'0' * 200}".b }

        it 'raises InvalidState, leaving the console as it was', :aggregate_failures do
          cycles = console.cpu.cycles

          expect { state.restore(other_format) }
            .to raise_error(Ruby::Nes::Saves::InvalidState, 'saved in another format')
          expect(console.cpu.cycles).to eq(cycles)
        end
      end

      context 'and the format is this one' do
        context 'but the header was cut short' do
          let(:saved_console) { Ruby::Nes::Console.new(Cartridges.with_program([0x4C, 0x00, 0x80])) }
          let(:cut_header) { described_class.new(saved_console).encode.byteslice(0, 100) }

          it 'raises InvalidState, leaving the console as it was', :aggregate_failures do
            cycles = console.cpu.cycles

            expect { state.restore(cut_header) }.to raise_error(Ruby::Nes::Saves::InvalidState, 'damaged')
            expect(console.cpu.cycles).to eq(cycles)
          end
        end

        context 'and the header is whole' do
          context 'but the ROM is another' do
            # NOP, forever.
            let(:other_console) { Ruby::Nes::Console.new(Cartridges.with_program([0xEA])) }

            before { other_console.run_frame }

            it 'raises InvalidState, leaving the console as it was', :aggregate_failures do
              cycles = console.cpu.cycles

              expect { state.restore(described_class.new(other_console).encode) }
                .to raise_error(Ruby::Nes::Saves::InvalidState, 'saved from another ROM')
              expect(console.cpu.cycles).to eq(cycles)
            end
          end

          context 'and the ROM is the console\'s' do
            context 'but the state was saved with the sound off and the console has sound' do
              let(:console_with_sound) do
                Ruby::Nes::Console.new(Cartridges.with_program([0x4C, 0x00, 0x80]), audio_sample_rate: 48_000)
              end
              let(:silent_state) { described_class.new(console).encode }

              it 'raises InvalidState naming --no-audio, leaving the console as it was', :aggregate_failures do
                cycles = console_with_sound.cpu.cycles

                expect { described_class.new(console_with_sound).restore(silent_state) }
                  .to raise_error(Ruby::Nes::Saves::InvalidState, 'saved with the sound off (--no-audio)')
                expect(console_with_sound.cpu.cycles).to eq(cycles)
              end
            end

            context 'but the state was saved with the sound on and the console has none' do
              let(:console_with_sound) do
                Ruby::Nes::Console.new(Cartridges.with_program([0x4C, 0x00, 0x80]), audio_sample_rate: 48_000)
              end

              before { console_with_sound.run_frame }

              it 'raises InvalidState naming --no-audio, leaving the console as it was', :aggregate_failures do
                cycles = console.cpu.cycles

                expect { state.restore(described_class.new(console_with_sound).encode) }
                  .to raise_error(Ruby::Nes::Saves::InvalidState, 'saved with the sound on (without --no-audio)')
                expect(console.cpu.cycles).to eq(cycles)
              end
            end

            context 'and the sound is as the console\'s' do
              # The same 16 KiB of PRG ROM and 8 KiB of CHR ROM on an MMC1 board: the ROM's digest is the same, and the
              # console holds other objects.
              context 'but the shape is another' do
                let(:other_console) do
                  Ruby::Nes::Console.new(Cartridges.with_program([0x4C, 0x00, 0x80], mapper_number: 1))
                end

                before { other_console.run_frame }

                it 'raises InvalidState, leaving the console as it was', :aggregate_failures do
                  cycles = console.cpu.cycles

                  expect { state.restore(described_class.new(other_console).encode) }
                    .to raise_error(Ruby::Nes::Saves::InvalidState, 'saved by another version of ruby-nes')
                  expect(console.cpu.cycles).to eq(cycles)
                end
              end

              context 'and the shape is the console\'s' do
                let(:saved_console) { Ruby::Nes::Console.new(Cartridges.with_program([0x4C, 0x00, 0x80])) }
                let(:saved_state) { described_class.new(saved_console).encode }

                before { saved_console.run_frame }

                context 'but the compressed snapshot was cut short' do
                  let(:cut_state) { saved_state.byteslice(0, saved_state.bytesize - 10) }

                  it 'raises InvalidState, leaving the console as it was', :aggregate_failures do
                    cycles = console.cpu.cycles

                    expect { state.restore(cut_state) }.to raise_error(Ruby::Nes::Saves::InvalidState, 'damaged')
                    expect(console.cpu.cycles).to eq(cycles)
                  end
                end

                # What a change the fingerprint misses would give: a Data's members, a Hash's keys.
                context 'but the snapshot inside cannot be loaded' do
                  let(:unloadable_state) do
                    saved_state.byteslice(0, described_class::HEADER_SIZE) + Zlib::Deflate.deflate('not a snapshot')
                  end

                  it 'raises InvalidState, leaving the console as it was', :aggregate_failures do
                    cycles = console.cpu.cycles

                    expect { state.restore(unloadable_state) }
                      .to raise_error(Ruby::Nes::Saves::InvalidState, 'cannot be read by this version of ruby-nes')
                    expect(console.cpu.cycles).to eq(cycles)
                  end
                end

                context 'and the state is whole' do
                  it 'brings the console to the moment it was saved' do
                    state.restore(saved_state)

                    expect(console.cpu.cycles).to eq(saved_console.cpu.cycles)
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
