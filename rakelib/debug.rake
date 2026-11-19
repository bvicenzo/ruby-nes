# frozen_string_literal: true

namespace :debug do
  desc 'Run a ROM from reset for some frames and write the last frame as a PPM image'
  task :frame, %i[rom frame_count output] do |_task, arguments|
    # Loaded here, not at the top: other rake tasks (build, rubocop) must not depend on the emulator loading.
    require_relative '../lib/ruby/nes'

    abort 'usage: rake "debug:frame[rom.nes,frame_count,output.ppm]"' unless arguments[:rom] && arguments[:output]

    console = Ruby::Nes::Console.new(Ruby::Nes::Cartridge::Loader.from_file(arguments[:rom]))
    frame_count = arguments[:frame_count].to_s.empty? ? 1 : Integer(arguments[:frame_count])
    abort 'frame_count must be at least 1' if frame_count < 1

    frame_count.times { console.run_frame }
    File.binwrite(arguments[:output], Ruby::Nes::Debug::FrameDump.ppm(console.ppu.frame_buffer))
    puts "Frame #{console.ppu.frame_number - 1} written to #{arguments[:output]}"
  end
end
