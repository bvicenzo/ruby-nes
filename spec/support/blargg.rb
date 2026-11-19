# frozen_string_literal: true

# blargg's test ROMs (instr_test-v5, ppu_vbl_nmi, instr_misc, cpu_interrupts_v2, ppu_open_bus...) report through PRG
# RAM, "Output at $6000" in each suite's readme: see plans/12-ppu-timing-vblank-nmi.md. Test tooling, required by the
# specs and rakelib/.
module Blargg
end

require_relative 'blargg/report'
require_relative 'blargg/runner'
require_relative 'blargg/programs'
