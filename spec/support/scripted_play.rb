# frozen_string_literal: true

require 'ruby/nes/frontends/input_script'

# Plays a console frame by frame, holding on the first controller the buttons a Frontends::InputScript gives for each
# frame (numbered from 1, as the headless frontend numbers them), and keeps a copy of each frame of the range asked
# for, since the console draws over its frame buffers (docs/architecture.md, Frame buffer contract).
#
#   ScriptedPlay.new(console, Ruby::Nes::Frontends::InputScript.parse("450: [start]\n456: []")).frames(1300..1399)
class ScriptedPlay
  def initialize(console, input_script)
    @console = console
    @input_script = input_script
  end

  # Runs frames 1 to the range's last and returns copies of the range's frames.
  def frames(range)
    (1..range.last).filter_map do |frame|
      @console.controllers.first.buttons = @input_script.buttons_at(frame)
      @console.run_frame
      @console.ppu.frame_buffer.dup if range.cover?(frame)
    end
  end
end
