# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'tmpdir'
require 'ruby/nes/frontends/base'
require 'ruby/nes/frontends/driver'
require 'ruby/nes/frontends/input_script'
require 'ruby/nes/frontends/palette'
require 'ruby/nes/frontends/png'
require 'ruby/nes/frontends/headless'

# The headless frontend (plan 16): no window and no sound. It runs a number of frames, counted from 1 (decision 6),
# holds the input script's buttons on the first controller, writes PNG screenshots of the frames asked for, and keeps
# the SHA-256 of each frame's pixels as 16-bit little-endian integers (pixels go up to 511, decision 2).
RSpec.describe Ruby::Nes::Frontends::Headless do
  describe '#running?' do
    context 'when fewer frames than asked were presented' do
      subject(:frontend) { described_class.new(frames: 2) }

      before { frontend.present([0x0F]) }

      it 'is true' do
        expect(frontend).to be_running
      end
    end

    context 'when as many frames as asked were presented' do
      subject(:frontend) { described_class.new(frames: 2) }

      before { 2.times { frontend.present([0x0F]) } }

      it 'is false' do
        expect(frontend).not_to be_running
      end
    end
  end

  describe '#button_states' do
    let(:input_script) { Ruby::Nes::Frontends::InputScript.new({ 1 => 0x08, 2 => 0x81 }) }

    context 'when no frame was presented' do
      subject(:frontend) { described_class.new(frames: 3, input_script:) }

      it "holds the script's buttons of frame 1 on the first controller only" do
        expect(frontend.button_states).to eq([0x08, 0x00])
      end
    end

    context 'when a frame was presented' do
      subject(:frontend) { described_class.new(frames: 3, input_script:) }

      before { frontend.present([0x0F]) }

      it "holds the script's buttons of the next frame on the first controller only" do
        expect(frontend.button_states).to eq([0x81, 0x00])
      end
    end
  end

  describe '#present' do
    let(:directory) { Dir.mktmpdir }
    let(:screenshot_path) { File.join(directory, 'second.png') }
    let(:picture_size) { Ruby::Nes::Ppu::Picture::WIDTH * Ruby::Nes::Ppu::Picture::HEIGHT }
    let(:first_frame) { Array.new(picture_size, 0x0F) }
    let(:second_frame) { Array.new(picture_size, 0x130) }

    after { FileUtils.remove_entry(directory) }

    context 'when no screenshot is asked for the frame presented' do
      subject(:frontend) { described_class.new(frames: 2, screenshots: { 2 => screenshot_path }) }

      before { frontend.present(first_frame) }

      it 'writes no file' do
        expect(Dir.children(directory)).to be_empty
      end
    end

    context 'when a screenshot is asked for the frame presented' do
      subject(:frontend) { described_class.new(frames: 2, screenshots: { 2 => screenshot_path }) }

      before do
        frontend.present(first_frame)
        frontend.present(second_frame)
      end

      it 'writes the frame as a PNG image at the path asked' do
        expected_image = Ruby::Nes::Frontends::Png.encode(
          width: Ruby::Nes::Ppu::Picture::WIDTH,
          height: Ruby::Nes::Ppu::Picture::HEIGHT,
          rgb: Ruby::Nes::Frontends::Palette.rgb(second_frame)
        )
        expect(File.binread(screenshot_path)).to eq(expected_image)
      end
    end
  end

  describe '#digests' do
    context 'when no frame was presented' do
      subject(:frontend) { described_class.new(frames: 2) }

      it 'is empty' do
        expect(frontend.digests).to be_empty
      end
    end

    context 'when frames were presented' do
      subject(:frontend) { described_class.new(frames: 2) }

      let(:first_frame) { [0x0F, 0x30] }
      let(:second_frame) { [0x10F, 0x30] }

      before do
        frontend.present(first_frame)
        frontend.present(second_frame)
      end

      it "holds the SHA-256 of each frame's pixels as 16-bit little-endian integers, in order" do
        expect(frontend.digests).to eq(
          [Digest::SHA256.hexdigest(first_frame.pack('S<*')), Digest::SHA256.hexdigest(second_frame.pack('S<*'))]
        )
      end
    end

    context 'when nestest runs twice from power-up, with the same input script', test_rom: Nestest::ROM_PATH do
      let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(test_rom_path(Nestest::ROM_PATH)) }
      let(:input_script) { Ruby::Nes::Frontends::InputScript.new({ 3 => 0x20, 4 => 0x00 }) }
      let(:first_run) { described_class.new(frames: 6, input_script:) }
      let(:second_run) { described_class.new(frames: 6, input_script:) }

      before do
        Ruby::Nes::Frontends::Driver.new(console: Ruby::Nes::Console.new(cartridge), frontend: first_run).run
        Ruby::Nes::Frontends::Driver.new(console: Ruby::Nes::Console.new(cartridge), frontend: second_run).run
      end

      it 'holds the same digests', :aggregate_failures do
        expect(first_run.digests.size).to eq(6)
        expect(second_run.digests).to eq(first_run.digests)
      end
    end
  end
end
