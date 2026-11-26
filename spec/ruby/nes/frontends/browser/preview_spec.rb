# frozen_string_literal: true

require 'ruby/nes/frontends/browser'

# The preview of the game in focus in the ROM browser (plan 37, decision 2). On focus, a game ruby-nes can run gets a
# console of its own, silent and without its battery save; its cached preview state (Browser::PreviewCache, by the
# ROM's SHA-256) is restored at once, and its picture is the still picture. Once the cursor has rested on the game for
# 30 frames (ticks), the console runs a frame on each tick after: from the cached state, or else from power-up, watched
# (Browser::MotionWatch) until its picture moves or the frame limit passes, when its state is cached, once. A state
# ruby-nes refuses is as none cached, and made again. A ROM that cannot be run or loaded shows no picture, and nothing
# breaks; one whose cartridge cannot be loaded gives the reason, printable, for the screen to show.
RSpec.describe Ruby::Nes::Frontends::Browser::Preview do
  describe '#focus' do
    context 'when another game was being watched' do
      subject(:preview) { described_class.new(cache:, load_cartridge:, new_motion_watch:, frame_limit: 10) }

      let(:cartridge) { Cartridges.with_program(Cartridges::BACKDROP_PROGRAM) }
      let(:load_cartridge) { ->(_path) { cartridge } }
      let(:still) { instance_double(Ruby::Nes::Frontends::Browser::MotionWatch, watch: nil, moving?: false) }
      let(:new_motion_watch) { -> { still } }
      let(:cache) { instance_double(Ruby::Nes::Frontends::Browser::PreviewCache, read: nil, write: nil) }
      let(:first_rom) { BrowserRoms.build(path: 'roms/Backdrop.nes') }
      let(:second_rom) { BrowserRoms.build(path: 'roms/Other.nes') }

      # Five frames of the first game watched, then nine of the second: fewer than the limit of 10 each.
      before do
        preview.focus(first_rom)
        35.times { preview.tick }
      end

      it 'watches the new one from its own first frame' do
        preview.focus(second_rom)
        39.times { preview.tick }

        expect(cache).not_to have_received(:write)
      end
    end

    context 'when the ROM cannot be run' do
      subject(:preview) { described_class.new(cache:) }

      let(:cache) { instance_double(Ruby::Nes::Frontends::Browser::PreviewCache, read: nil, write: nil) }
      let(:rom) { BrowserRoms.build(problem: 'MAPPER 5 IS NOT SUPPORTED') }

      it 'shows no picture, even once the cursor rests', :aggregate_failures do
        preview.focus(rom)
        40.times { preview.tick }

        expect(preview.frame_buffer).to be_nil
        expect(cache).not_to have_received(:read)
      end
    end

    context 'when the ROM can be run' do
      context 'but its cartridge cannot be loaded' do
        subject(:preview) { described_class.new(cache:, load_cartridge:) }

        let(:cache) { instance_double(Ruby::Nes::Frontends::Browser::PreviewCache, read: nil, write: nil) }
        let(:load_cartridge) { ->(_path) { raise Ruby::Nes::Cartridge::TruncatedImage, 'image has 16 bytes' } }
        let(:rom) { BrowserRoms.build(path: 'roms/Short.nes') }

        it 'shows no picture, even once the cursor rests, and gives the reason, printable', :aggregate_failures do
          preview.focus(rom)
          40.times { preview.tick }

          expect(preview.frame_buffer).to be_nil
          expect(preview.problem).to eq('IMAGE HAS 16 BYTES')
          expect(cache).not_to have_received(:write)
        end
      end

      context 'and it loads' do
        context 'but no preview was cached' do
          subject(:preview) { described_class.new(cache:, load_cartridge:) }

          # Its frames hold the backdrop colour $21, where a console at power-up has drawn nothing (0).
          let(:cartridge) { Cartridges.with_program(Cartridges::BACKDROP_PROGRAM) }
          let(:load_cartridge) { ->(_path) { cartridge } }
          let(:cache) { instance_double(Ruby::Nes::Frontends::Browser::PreviewCache, read: nil, write: nil) }
          let(:rom) { BrowserRoms.build(path: 'roms/Backdrop.nes') }

          it 'shows no picture until it runs' do
            preview.focus(rom)

            expect(preview.frame_buffer).to be_nil
          end
        end

        context 'and a preview was cached' do
          context 'but ruby-nes refuses it' do
            subject(:preview) { described_class.new(cache:, load_cartridge:, new_motion_watch:) }

            let(:cartridge) { Cartridges.with_program(Cartridges::BACKDROP_PROGRAM) }
            let(:load_cartridge) { ->(_path) { cartridge } }
            let(:moving) { instance_double(Ruby::Nes::Frontends::Browser::MotionWatch, watch: nil, moving?: true) }
            let(:new_motion_watch) { -> { moving } }
            let(:first_frame_console) { Ruby::Nes::Console.new(cartridge).tap(&:run_frame) }
            let(:rom_digest) { Ruby::Nes::Saves::ConsoleState.new(Ruby::Nes::Console.new(cartridge)).rom_digest }
            let(:cache) do
              instance_double(Ruby::Nes::Frontends::Browser::PreviewCache, read: 'not a state', write: nil)
            end
            let(:rom) { BrowserRoms.build(path: 'roms/Backdrop.nes') }

            it 'shows no picture until it runs' do
              preview.focus(rom)

              expect(preview.frame_buffer).to be_nil
            end

            it 'makes it again from power-up' do
              preview.focus(rom)
              31.times { preview.tick }

              expect(cache).to have_received(:write)
                .with(rom_digest, Ruby::Nes::Saves::ConsoleState.new(first_frame_console).encode)
            end
          end

          context 'and ruby-nes restores it' do
            subject(:preview) { described_class.new(cache:, load_cartridge:) }

            let(:cartridge) { Cartridges.with_program(Cartridges::BACKDROP_PROGRAM) }
            let(:load_cartridge) { ->(_path) { cartridge } }
            # The console of the cached preview, two frames from power-up.
            let(:saved_console) { Ruby::Nes::Console.new(cartridge).tap { |console| 2.times { console.run_frame } } }
            let(:cache) do
              instance_double(
                Ruby::Nes::Frontends::Browser::PreviewCache,
                read: Ruby::Nes::Saves::ConsoleState.new(saved_console).encode,
                write: nil
              )
            end
            let(:rom) { BrowserRoms.build(path: 'roms/Backdrop.nes') }

            it 'shows its picture at once' do
              preview.focus(rom)

              expect(preview.frame_buffer).to eq(saved_console.ppu.frame_buffer).and include(0x21)
            end
          end
        end
      end
    end
  end

  describe '#tick' do
    context 'when the cursor has rested 30 frames or fewer' do
      subject(:preview) { described_class.new(cache:, load_cartridge:) }

      let(:cartridge) { Cartridges.with_program(Cartridges::BACKDROP_PROGRAM) }
      let(:load_cartridge) { ->(_path) { cartridge } }
      let(:cache) { instance_double(Ruby::Nes::Frontends::Browser::PreviewCache, read: nil, write: nil) }
      let(:rom) { BrowserRoms.build(path: 'roms/Backdrop.nes') }

      it 'runs nothing yet' do
        preview.focus(rom)
        30.times { preview.tick }

        expect(preview.frame_buffer).to be_nil
      end
    end

    context 'when the cursor has rested longer' do
      context 'and a preview was cached' do
        subject(:preview) { described_class.new(cache:, load_cartridge:) }

        let(:cartridge) { Cartridges.with_program(Cartridges::BACKDROP_PROGRAM) }
        let(:load_cartridge) { ->(_path) { cartridge } }
        # The console of the cached preview, two frames from power-up, and one that ran three more.
        let(:saved_console) { Ruby::Nes::Console.new(cartridge).tap { |console| 2.times { console.run_frame } } }
        let(:later_console) { Ruby::Nes::Console.new(cartridge).tap { |console| 5.times { console.run_frame } } }
        let(:cache) do
          instance_double(
            Ruby::Nes::Frontends::Browser::PreviewCache,
            read: Ruby::Nes::Saves::ConsoleState.new(saved_console).encode,
            write: nil
          )
        end
        let(:rom) { BrowserRoms.build(path: 'roms/Backdrop.nes') }

        it 'runs a frame per tick from the cached moment, caching nothing', :aggregate_failures do
          preview.focus(rom)
          33.times { preview.tick }

          expect(preview.frame_buffer).to eq(later_console.ppu.frame_buffer)
          expect(cache).not_to have_received(:write)
        end
      end

      context 'and none was' do
        context 'but the picture is still, within the frame limit' do
          subject(:preview) { described_class.new(cache:, load_cartridge:, new_motion_watch:, frame_limit: 10) }

          let(:cartridge) { Cartridges.with_program(Cartridges::BACKDROP_PROGRAM) }
          let(:load_cartridge) { ->(_path) { cartridge } }
          let(:still) { instance_double(Ruby::Nes::Frontends::Browser::MotionWatch, watch: nil, moving?: false) }
          let(:new_motion_watch) { -> { still } }
          # A console that ran nine frames from power-up.
          let(:later_console) { Ruby::Nes::Console.new(cartridge).tap { |console| 9.times { console.run_frame } } }
          let(:cache) { instance_double(Ruby::Nes::Frontends::Browser::PreviewCache, read: nil, write: nil) }
          let(:rom) { BrowserRoms.build(path: 'roms/Backdrop.nes') }

          it 'runs from power-up, caching nothing', :aggregate_failures do
            preview.focus(rom)
            39.times { preview.tick }

            expect(preview.frame_buffer).to eq(later_console.ppu.frame_buffer)
            expect(cache).not_to have_received(:write)
          end
        end

        context 'and the picture starts moving' do
          subject(:preview) { described_class.new(cache:, load_cartridge:, new_motion_watch:, frame_limit: 10) }

          let(:cartridge) { Cartridges.with_program(Cartridges::BACKDROP_PROGRAM) }
          let(:load_cartridge) { ->(_path) { cartridge } }
          # Still for two frames, moving from the third.
          let(:watch) do
            instance_double(Ruby::Nes::Frontends::Browser::MotionWatch, watch: nil).tap do |watch|
              allow(watch).to receive(:moving?).and_return(false, false, true)
            end
          end
          let(:new_motion_watch) { -> { watch } }
          let(:third_frame_console) do
            Ruby::Nes::Console.new(cartridge).tap { |console| 3.times { console.run_frame } }
          end
          let(:rom_digest) { Ruby::Nes::Saves::ConsoleState.new(Ruby::Nes::Console.new(cartridge)).rom_digest }
          let(:cache) { instance_double(Ruby::Nes::Frontends::Browser::PreviewCache, read: nil, write: nil) }
          let(:rom) { BrowserRoms.build(path: 'roms/Backdrop.nes') }

          it 'caches the state of the frame it started moving, once' do
            preview.focus(rom)
            39.times { preview.tick }

            expect(cache).to have_received(:write)
              .once
              .with(rom_digest, Ruby::Nes::Saves::ConsoleState.new(third_frame_console).encode)
          end
        end

        context 'and the frame limit passes without motion' do
          subject(:preview) { described_class.new(cache:, load_cartridge:, new_motion_watch:, frame_limit: 4) }

          let(:cartridge) { Cartridges.with_program(Cartridges::BACKDROP_PROGRAM) }
          let(:load_cartridge) { ->(_path) { cartridge } }
          let(:still) { instance_double(Ruby::Nes::Frontends::Browser::MotionWatch, watch: nil, moving?: false) }
          let(:new_motion_watch) { -> { still } }
          let(:fourth_frame_console) do
            Ruby::Nes::Console.new(cartridge).tap { |console| 4.times { console.run_frame } }
          end
          let(:rom_digest) { Ruby::Nes::Saves::ConsoleState.new(Ruby::Nes::Console.new(cartridge)).rom_digest }
          let(:cache) { instance_double(Ruby::Nes::Frontends::Browser::PreviewCache, read: nil, write: nil) }
          let(:rom) { BrowserRoms.build(path: 'roms/Backdrop.nes') }

          it 'caches the state of the last frame within it, once' do
            preview.focus(rom)
            39.times { preview.tick }

            expect(cache).to have_received(:write)
              .once
              .with(rom_digest, Ruby::Nes::Saves::ConsoleState.new(fourth_frame_console).encode)
          end
        end
      end
    end
  end
end
