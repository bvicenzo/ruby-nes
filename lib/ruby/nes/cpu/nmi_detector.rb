# frozen_string_literal: true

module Ruby
  module Nes
    class Cpu
      # The NMI edge detector (https://www.nesdev.org/wiki/CPU_interrupts). It "polls the status of the NMI line during
      # φ2 of each CPU cycle" and notices a released-to-asserted change; the internal signal "stays high until the NMI
      # has been handled", so releasing the line does not cancel it and holding it asserted does not repeat it. The PPU
      # tells each change with the first CPU cycle whose φ2 sample sees it (plan 12, decision 2): a line released
      # within the cycle it rose in leaves no edge, which is how a $2002 read right after VBlank starts suppresses the
      # NMI. A second edge while one is pending keeps the first one's cycle. Booleans only: the integer 0 would read as
      # asserted.
      class NmiDetector
        def initialize
          @line = false
          @pending = false
          @edge_cycle = 0
        end

        # The NMI line's new level, `true` while asserted, and the CPU cycle the change happened on.
        def line_changed(asserted, cycle)
          if asserted && !@line && !@pending
            @pending = true
            @edge_cycle = cycle
          elsif !asserted && @pending && @edge_cycle == cycle
            # Released before the φ2 sample of the cycle it rose in: the detector never saw it low.
            @pending = false
          end
          @line = asserted
        end

        # Whether an NMI is pending whose edge came before `poll_cycle`.
        def pending_before?(poll_cycle) = @pending && @edge_cycle < poll_cycle

        # The NMI was handled, or reset forgot it (plan 07, decision 6); the line keeps its level.
        def clear_pending
          @pending = false
        end
      end
    end
  end
end
