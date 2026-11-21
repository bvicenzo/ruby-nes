# Test ROMs

The community test ROMs the suite runs, fetched by `bundle exec rake test_roms:fetch` from a pinned commit of
[christopherpow/nes-test-roms](https://github.com/christopherpow/nes-test-roms) and checked by SHA-256
(`spec/fixtures/test_roms.yml`, plan 02). They are never committed.

## How they run

- **nestest** (`other/nestest.nes`) runs in automation mode against `other/nestest.log`, compared line by line with
  the PPU column (plans 08 and 12): `rake nestest:diff`.
- **blargg's suites** report through PRG RAM ("Output at $6000" in each readme): status at `$6000`, `$DE $B0 $61` at
  `$6001-$6003`, text from `$6004`. `Blargg::Runner` (`spec/support/blargg/`) runs a console frame by frame, presses
  reset 7 frames (116 ms) after a `$81` request, and stops at a result or after 3600 frames.
  `rake 'blargg:run[<path>]'` prints one ROM's outcome.
- **blargg's 2005 suites** (`sprite_hit_tests_2005.10.05`, `sprite_overflow_tests`) report "on screen and by beeping";
  their source keeps the result at `$F8` (1 passed, otherwise the failing test's number) and ends in `exit: jmp exit`.
  `Blargg::LegacyReport` reads it once the CPU sits on that loop (plan 14); `rake blargg:run` picks it for those
  suites.
- **blargg's older shell** (`cpu_dummy_reads`) writes nothing at `$6000`: its text console draws on nametable 0 with
  ASCII tiles and ends with a line `Passed`, `Failed` or `Error <code>`. `Blargg::ScreenReport` reads that line through
  the console's PPU bus (plan 19); `rake blargg:run` picks it for that ROM.
- The ROMs that must pass are examples of `spec/blargg/runner_spec.rb`, tagged `slow: true`: they run with `SLOW=1`
  and always in CI's `test-roms` job, under YJIT (plan 12, decision 6). The others are recorded here.

The single-test builds run here are NROM boards, `cpu_dummy_reads.nes` a CNROM one (plan 19) and the multi-test builds
(`all_instrs.nes`, `official_only.nes`, `ppu_vbl_nmi.nes`, `cpu_interrupts.nes`) MMC1 ones (plan 20). The collection
has no multi-mapper ROM such as Holy Mapperel at the pinned commit (plan 19, decision 9). Two more MMC1 ROMs are in the
collection and not run: `MMC1_A12/mmc1_a12.nes` is interactive (it reads the joypad and reports nothing automatically)
and `instr_timing` times instructions with the APU (plan 22).

## Results

Plan 12, 2026-11-19, after the review's fixes. Frames are emulated frames until the result; times are under YJIT on the machine of
[benchmarks](benchmarks.md).

| ROM | Result | Frames | Notes |
|---|---|---|---|
| `other/nestest.nes` | Passed | — | All 8991 lines of nestest.log match, PPU column included; `$0002` and `$0003` are `$00`. |
| `instr_test-v5/rom_singles/01-basics.nes` | Passed | 20 | |
| `instr_test-v5/rom_singles/02-implied.nes` | Passed | 98 | |
| `instr_test-v5/rom_singles/03-immediate.nes` | Passed | 88 | Needs `LAX #imm` with $FF (architecture decision 29); with $EE it fails "AB ATX #n". |
| `instr_test-v5/rom_singles/04-zero_page.nes` | Passed | 118 | |
| `instr_test-v5/rom_singles/05-zp_xy.nes` | Passed | 263 | |
| `instr_test-v5/rom_singles/06-absolute.nes` | Passed | 111 | |
| `instr_test-v5/rom_singles/07-abs_xy.nes` | Passed | 367 | Includes `SHX` and `SHY`. |
| `instr_test-v5/rom_singles/08-ind_x.nes` | Passed | 148 | |
| `instr_test-v5/rom_singles/09-ind_y.nes` | Passed | 138 | |
| `instr_test-v5/rom_singles/10-branches.nes` | Passed | 42 | |
| `instr_test-v5/rom_singles/11-stack.nes` | Passed | 166 | |
| `instr_test-v5/rom_singles/12-jmp_jsr.nes` | Passed | 18 | |
| `instr_test-v5/rom_singles/13-rts.nes` | Passed | 16 | |
| `instr_test-v5/rom_singles/14-rti.nes` | Passed | 15 | |
| `instr_test-v5/rom_singles/15-brk.nes` | Passed | 26 | |
| `instr_test-v5/rom_singles/16-special.nes` | Passed | 15 | |
| `ppu_vbl_nmi/rom_singles/01-vbl_basics.nes` | Passed | 143 | |
| `ppu_vbl_nmi/rom_singles/02-vbl_set_time.nes` | Passed | 172 | |
| `ppu_vbl_nmi/rom_singles/03-vbl_clear_time.nes` | Passed | 172 | |
| `ppu_vbl_nmi/rom_singles/04-nmi_control.nes` | Passed | 38 | Needs the register-access sync and the NMI polling point (architecture decisions 23 and 24). |
| `ppu_vbl_nmi/rom_singles/05-nmi_timing.nes` | Passed | 222 | Needs the φ2 sampling of the NMI line: a change on a CPU cycle's last dot is seen in the next cycle (architecture decision 24). |
| `ppu_vbl_nmi/rom_singles/06-suppression.nes` | Passed | 225 | A `$2002` read on the dot VBlank starts or the next one releases /NMI before the CPU's φ2 sample, so no edge is seen (decision 24); the read on the dot before cancels the flag itself (decision 5 of plan 12). |
| `ppu_vbl_nmi/rom_singles/07-nmi_on_timing.nes` | Passed | 200 | Enabling NMI right before the flag clears asserts and releases /NMI before the φ2 sample (decision 24). |
| `ppu_vbl_nmi/rom_singles/08-nmi_off_timing.nes` | Passed | 224 | Disabling NMI right after VBlank starts releases /NMI before the φ2 sample (decision 24). |
| `ppu_vbl_nmi/rom_singles/09-even_odd_frames.nes` | Passed | 71 | |
| `ppu_vbl_nmi/rom_singles/10-even_odd_timing.nes` | Failed (3) | 82 | "Clock is skipped too late, relative to enabling BG": rendering takes effect at once, not 3-4 dots later (Known gaps: rendering toggle delay). |
| `instr_misc/rom_singles/01-abs_x_wrap.nes` | Passed | 12 | |
| `instr_misc/rom_singles/02-branch_wrap.nes` | Passed | 11 | |
| `instr_misc/rom_singles/03-dummy_reads.nes` | Passed | 57 | Needs the indexed dummy reads (architecture decision 26). |
| `cpu_interrupts_v2/rom_singles/1-cli_latency.nes` | Failed (3) | 19 | "APU should generate IRQ when $4017 = $00": needs the APU frame IRQ (plan 22). |
| `cpu_interrupts_v2/rom_singles/2-nmi_and_brk.nes` | Failed (1) | 124 | An NMI during `BRK`: probably the hijacking, not modelled (plan 22). |
| `cpu_interrupts_v2/rom_singles/3-nmi_and_irq.nes` | Failed (1) | 139 | Needs the APU frame IRQ (plan 22). |
| `cpu_interrupts_v2/rom_singles/4-irq_and_dma.nes` | Failed (1) | 70 | Needs the APU frame IRQ (plan 22). |
| `cpu_interrupts_v2/rom_singles/5-branch_delays_irq.nes` | Timed out | 3600 | Stays at "test_jmp" waiting for an IRQ: needs the APU frame IRQ (plan 22). |
| `ppu_open_bus/ppu_open_bus.nes` | Failed (3) | 73 | "Decay value should become zero by one second": the I/O latch does not decay (plan 12, decision 9). |

Plan 14, 2026-11-19, sprite suites (code `$01` is passed). Frames until the result; times under YJIT, one ROM at a
time, on the machine of [benchmarks](benchmarks.md) (about 1.5 s each).

| ROM | Result | Frames | Notes |
|---|---|---|---|
| `sprite_hit_tests_2005.10.05/01.basics.nes` | Passed | 46 | |
| `sprite_hit_tests_2005.10.05/02.alignment.nes` | Passed | 44 | |
| `sprite_hit_tests_2005.10.05/03.corners.nes` | Passed | 34 | |
| `sprite_hit_tests_2005.10.05/04.flip.nes` | Passed | 32 | |
| `sprite_hit_tests_2005.10.05/05.left_clip.nes` | Passed | 42 | |
| `sprite_hit_tests_2005.10.05/06.right_edge.nes` | Passed | 36 | |
| `sprite_hit_tests_2005.10.05/07.screen_bottom.nes` | Passed | 38 | |
| `sprite_hit_tests_2005.10.05/08.double_height.nes` | Passed | 34 | |
| `sprite_hit_tests_2005.10.05/09.timing_basics.nes` | Passed | 83 | Timing to "within 12 or so PPU clocks"; passes with the hit set on dot x + 1 (plan 14, decision 9). |
| `sprite_hit_tests_2005.10.05/10.timing_order.nes` | Passed | 79 | |
| `sprite_hit_tests_2005.10.05/11.edge_timing.nes` | Passed | 59 | |
| `sprite_overflow_tests/1.Basics.nes` | Passed | 29 | |
| `sprite_overflow_tests/2.Details.nes` | Passed | 37 | |
| `sprite_overflow_tests/3.Timing.nes` | Failed (5) | 116 | "Set too late for first scanline": the evaluation runs whole at dot 257 (Known gaps: sprite overflow timing). |
| `sprite_overflow_tests/4.Obscure.nes` | Passed | 36 | Needs the diagonal scan of the overflow search. |
| `sprite_overflow_tests/5.Emulator.nes` | Passed | 27 | |

Plan 19, 2026-11-20, the first ROM on a board other than NROM.

| ROM | Result | Frames | Notes |
|---|---|---|---|
| `cpu_dummy_reads/cpu_dummy_reads.nes` | Passed | 45 | CNROM (mapper 3), read through `Blargg::ScreenReport`. Checks the dummy reads of `LDA`/`STA` absolute,X and (indirect),Y through `$2002` and `$2004`, and their absence in (indirect,X) (architecture decision 26). |

Plan 20, 2026-11-20, the multi-test builds on MMC1 (mapper 1). Times are under `rake blargg:run` without a JIT.

| ROM | Result | Frames | Notes |
|---|---|---|---|
| `instr_test-v5/all_instrs.nes` | Passed | 2397 | All 16 tests; 313 s without a JIT. |
| `instr_test-v5/official_only.nes` | Passed | 1872 | All 16 tests; 239 s without a JIT. |
| `ppu_vbl_nmi/ppu_vbl_nmi.nes` | Failed (3) | 1545 | Tests 1-9 pass; test 10, "Clock is skipped too late, relative to enabling BG", as its single build (Known gaps: rendering toggle delay). |
| `cpu_interrupts_v2/cpu_interrupts.nes` | Failed (3) | 26 | Test 1, "APU should generate IRQ when $4017 = $00", as its single build (plan 22). Its 80 KiB of PRG ROM is not a power of two: MMC1's mode 3 fixes the file's last bank (bank 4) at `$C000`, where bank 15 would wrap to bank 0 (plan 20, decision 9). |
