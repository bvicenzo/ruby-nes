# frozen_string_literal: true

require 'ruby/nes/command_line'

# The picture of a save state slot for the pause menu's slot picker (plan 38, decision 4): the frame on screen at the
# moment saved, read from the state itself, restored into a console of its own built from the same cartridge with the
# same sound (Saves::ConsoleState), so the playing console is left alone. A slot with no state, a state that cannot be
# read, one ruby-nes refuses, or a states folder that cannot be found have no picture. The boundary is the game's state
# files (bytes, nil, or a raise).
RSpec.describe Ruby::Nes::Saves::StatePictures do
  describe '#picture' do
    context 'when the states folder cannot be found' do
      subject(:pictures) { described_class.new(console:, files:) }

      let(:console) { Ruby::Nes::Console.new(Cartridges.with_program(Cartridges::BACKDROP_PROGRAM)) }
      let(:files) { instance_double(Ruby::Nes::Saves::StateFiles) }

      before { allow(files).to receive(:read).and_raise(Ruby::Nes::Saves::Error, 'no home directory') }

      it 'is nil' do
        expect(pictures.picture(3)).to be_nil
      end
    end

    context 'when the states folder is found' do
      context 'but the slot has no state' do
        subject(:pictures) { described_class.new(console:, files:) }

        let(:console) { Ruby::Nes::Console.new(Cartridges.with_program(Cartridges::BACKDROP_PROGRAM)) }
        let(:files) { instance_double(Ruby::Nes::Saves::StateFiles, read: nil) }

        it 'is nil' do
          expect(pictures.picture(3)).to be_nil
        end
      end

      context 'and the slot has a state' do
        context 'but it cannot be read' do
          subject(:pictures) { described_class.new(console:, files:) }

          let(:console) { Ruby::Nes::Console.new(Cartridges.with_program(Cartridges::BACKDROP_PROGRAM)) }
          let(:files) { instance_double(Ruby::Nes::Saves::StateFiles) }

          before { allow(files).to receive(:read).with(3).and_raise(Errno::EACCES) }

          it 'is nil' do
            expect(pictures.picture(3)).to be_nil
          end
        end

        context 'and it is read' do
          context 'but ruby-nes refuses it' do
            subject(:pictures) { described_class.new(console:, files:) }

            let(:console) { Ruby::Nes::Console.new(Cartridges.with_program(Cartridges::BACKDROP_PROGRAM)) }
            let(:files) { instance_double(Ruby::Nes::Saves::StateFiles, read: 'not a state') }

            it 'is nil' do
              expect(pictures.picture(3)).to be_nil
            end
          end

          context 'and ruby-nes restores it' do
            subject(:pictures) { described_class.new(console:, files:) }

            # A console of the same cartridge saved the state; its frames show the backdrop colour $21 once the first
            # VBlank has ended, where the playing console, at power-up, has drawn nothing (0).
            let(:cartridge) { Cartridges.with_program(Cartridges::BACKDROP_PROGRAM) }
            let(:console) { Ruby::Nes::Console.new(cartridge) }
            let(:saving_console) { Ruby::Nes::Console.new(cartridge) }
            let(:files) { instance_double(Ruby::Nes::Saves::StateFiles) }

            before do
              2.times { saving_console.run_frame }
              state_bytes = Ruby::Nes::Saves::ConsoleState.new(saving_console).encode
              allow(files).to receive(:read).with(3).and_return(state_bytes)
            end

            it "is the frame on screen at the moment saved, the playing console's left as it is", :aggregate_failures do
              expect(pictures.picture(3)).to eq(saving_console.ppu.frame_buffer).and include(0x21)
              expect(console.ppu.frame_buffer).to all(eq(0))
            end
          end
        end
      end
    end
  end
end
