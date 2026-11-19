# frozen_string_literal: true

module Ruby
  module Nes
    # Everything around the core that a person sees, hears and touches (docs/architecture.md, Frame buffer contract):
    # turning pixels into colours, presenting, pacing, reading input. The core never loads it.
    module Frontends
      # The contract between the emulator and a frontend (plan 16). Frontends::Driver runs the loop; a frontend
      # subclasses this and answers:
      #
      # - `running?`: whether to run another frame;
      # - `button_states`: the buttons held on both controllers, `[first, second]`, each a mask in report order
      #   (Input::Controller::BUTTONS, bit 0 = A … bit 7 = Right); the driver hands them to Console#controllers before
      #   each frame. Opposite directions are the frontend's to filter (plan 15, decision 2);
      # - `present(frame_buffer)`: once per frame, the frame the PPU completed, 256 × 240 pixels of 0-511 (a palette
      #   index plus the emphasis bits; Frontends::Palette turns them into RGB). The PPU draws the next frame over the
      #   same array, so a frontend that keeps it past `present` copies it;
      # - `queue_audio(samples)`: the audio samples of the frame; ignored until the APU exists (plan 24).
      class Base
        def running?
          raise NotImplementedError, "#{self.class} must implement running?"
        end

        def button_states
          raise NotImplementedError, "#{self.class} must implement button_states"
        end

        def present(_frame_buffer)
          raise NotImplementedError, "#{self.class} must implement present"
        end

        def queue_audio(_samples) = nil
      end
    end
  end
end
