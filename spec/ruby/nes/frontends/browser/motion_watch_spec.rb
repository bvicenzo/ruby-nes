# frozen_string_literal: true

require 'ruby/nes/frontends/browser'

# Whether a game left alone has started moving (plan 37, decision 2): told each frame it presents, the watch counts the
# different pictures shown in each second (60 frames, from the first frame watched). The first second that shows at
# least 30 different pictures marks the moving picture, an attract mode's demo or an animated title, as opposed to a
# still title whose text blinks, or that cycles through a few pictures, however often they change; from then on the
# picture is moving, whatever comes next.
RSpec.describe Ruby::Nes::Frontends::Browser::MotionWatch do
  describe '#moving?' do
    subject(:motion_watch) { described_class.new }

    context 'when fewer than 60 frames were watched' do
      # Each frame shows a picture of its own.
      before { 59.times { motion_watch.watch(Array.new(4, it)) } }

      it 'is false' do
        expect(motion_watch).not_to be_moving
      end
    end

    context 'when a second was watched' do
      context 'but it showed fewer than 30 different pictures' do
        # 29 pictures in turn: every frame differs from the one before.
        before { 60.times { motion_watch.watch(Array.new(4, it % 29)) } }

        it 'is false, however often they changed' do
          expect(motion_watch).not_to be_moving
        end
      end

      context 'and it showed 30' do
        before { 60.times { motion_watch.watch(Array.new(4, it % 30)) } }

        it 'is true' do
          expect(motion_watch).to be_moving
        end
      end
    end

    context 'when two seconds were watched' do
      context 'but neither showed 30 different pictures' do
        # 20 pictures in the first second, 20 others in the second.
        before { 120.times { motion_watch.watch(Array.new(4, (it % 20) + (it / 60 * 20))) } }

        it 'is false, counting each second on its own' do
          expect(motion_watch).not_to be_moving
        end
      end

      context 'and the first showed 30, and the second was still' do
        before { 120.times { motion_watch.watch(Array.new(4, [it, 29].min)) } }

        it 'stays true' do
          expect(motion_watch).to be_moving
        end
      end
    end

    # The six local games measured for plan 37 (Context); these two are the slowest to move from a still title.
    context 'when it watches a game left alone from power-up', :slow do
      context 'and the game is Castlevania', local_rom: 'Castlevania (USA) (Rev 1).nes' do
        let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(local_rom_path('Castlevania (USA) (Rev 1).nes')) }
        let(:console) { Ruby::Nes::Console.new(cartridge) }

        it 'turns true as its demo starts, after 14 seconds on its title' do
          frames = (1..3600).find do
            console.run_frame
            motion_watch.watch(console.ppu.frame_buffer)
            motion_watch.moving?
          end

          expect(frames).to eq(840)
        end
      end

      context 'and the game is Super Pitfall', local_rom: 'Super Pitfall (USA).nes' do
        let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(local_rom_path('Super Pitfall (USA).nes')) }
        let(:console) { Ruby::Nes::Console.new(cartridge) }

        it 'turns true as its demo starts, past 22 seconds of a title that blinks' do
          frames = (1..3600).find do
            console.run_frame
            motion_watch.watch(console.ppu.frame_buffer)
            motion_watch.moving?
          end

          expect(frames).to eq(1320)
        end
      end
    end
  end
end
