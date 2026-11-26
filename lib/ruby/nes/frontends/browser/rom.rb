# frozen_string_literal: true

module Ruby
  module Nes
    module Frontends
      module Browser
        # A ROM the browser lists (plan 37, scope 2): its `path`, the `name` and `tags` it shows (Browser::RomName), the
        # `problem` that keeps ruby-nes from running it, in upper case for the pixel font, or nil, and whether it has a
        # `battery_save` (plan 34) and `save_states` (plan 35).
        Rom = Data.define(:path, :name, :tags, :problem, :battery_save, :save_states)

        class Rom
          def playable? = problem.nil?
        end
      end
    end
  end
end
