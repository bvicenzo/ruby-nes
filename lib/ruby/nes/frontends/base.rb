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
      # - `paused?`: whether the emulation is paused: the driver then runs no frame and presents the last completed one
      #   again, so the frontend keeps drawing and pacing (plan 18, decision 5); false by default;
      # - `reset_requested?`: whether the console is to be reset (the reset button) before the next frame; false by
      #   default;
      # - `queue_audio(samples)`: the signed 16-bit audio samples of the frame just run, before it is presented (plan
      #   24); ignored by default;
      # - `state_action`: the save state action asked for before the next frame (Saves::StateSlots::ACTIONS), or nil;
      #   nil by default (plan 35);
      # - `notify(message)`: a short message to show the player ("State 3 saved"); shown nowhere by default;
      # - `discard_audio`: drops the audio queued and not yet played, after a state is loaded; nothing by default;
      # - `closed?`: whether the player closed the window, which ends the ROM browser too (plan 37); false by default;
      # - `next_screen`: the ROM browser goes from its list to a game or back (plan 37, decision 7): the frontend starts
      #   over, not paused nor quitting, its queued audio dropped, and the buttons held then are left out of
      #   `button_states` until let go (plan 38); nothing by default;
      # - `queue_silence`: a frame of silence for a screen with no sound, the ROM browser's list, so audio keeps pacing
      #   it (plan 37, decision 7); nothing by default;
      # - `menu_requested?`: whether the player asked for a menu (plan 38): the pause menu in a game, the list's menu in
      #   the ROM browser, closing a menu that is open; false by default;
      # - `leave`: a menu's order to end the screen, as BACK TO THE LIST does: `running?` turns false until
      #   `next_screen`; nothing by default;
      # - `quit`: a menu's order to end the session, as QUIT does: `closed?` turns true; nothing by default;
      # - `resume`: a menu closes over a game or the ROM list: the frontend starts over, not paused nor asking (a list
      #   paused with P is un-paused), and the buttons held then are left out of `button_states` until let go (plan 38,
      #   scope 3); nothing by default;
      # - `close`: once the run ends, however it ends, releases what the frontend opened (a window, an audio device;
      #   plan 17); nothing by default.
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

        def paused? = false

        def reset_requested? = false

        def queue_audio(_samples) = nil

        def state_action = nil

        def notify(_message) = nil

        def discard_audio = nil

        def closed? = false

        def next_screen = nil

        def queue_silence = nil

        def menu_requested? = false

        def leave = nil

        def quit = nil

        def resume = nil

        def close = nil
      end
    end
  end
end
