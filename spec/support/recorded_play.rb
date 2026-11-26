# frozen_string_literal: true

require 'digest'
require 'ruby/nes/frontends/input_script'

# Plays a console frame by frame, holding on the first controller the buttons a Frontends::InputScript gives for each
# frame (numbered from 1, as the headless frontend numbers them), and records what each frame of a range showed and
# played: its digest, over 16-bit pixels as the headless frontend hashes them (plan 16, decision 6), and its audio
# samples. Two recordings are equal when the console showed and played the same, frame by frame.
#
#   RecordedPlay.new(console, input_script).record(1251..1370)
class RecordedPlay
  Recording = Data.define(:frame_digests, :audio_samples)

  def initialize(console, input_script = Ruby::Nes::Frontends::InputScript::EMPTY)
    @console = console
    @input_script = input_script
  end

  # Runs the frames of `range`, the console standing at the end of the frame before its first, and returns their
  # recording.
  def record(range)
    frame_digests = []
    audio_samples = []
    range.each do |frame|
      @console.controllers.first.buttons = @input_script.buttons_at(frame)
      @console.run_frame
      frame_digests << Digest::SHA256.hexdigest(@console.ppu.frame_buffer.pack('S<*'))
      audio_samples.concat(@console.audio_samples)
    end
    Recording.new(frame_digests:, audio_samples:)
  end
end
