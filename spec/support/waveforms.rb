# frozen_string_literal: true

# `play_waveform(levels)`: the duty sequencer outputs `levels`, one per step, reading the output before each step from
# where it stands (Ruby::Nes::Apu::DutySequencer).
#
#   expect(sequencer).to play_waveform([0, 1, 0, 0, 0, 0, 0, 0])
RSpec::Matchers.define :play_waveform do |levels|
  match do |sequencer|
    @played = levels.map do
      level = sequencer.output
      sequencer.step
      level
    end
    @played == levels
  end

  failure_message { |_sequencer| "expected the waveform #{levels.inspect}, played #{@played.inspect}" }
end
