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
- The ROMs that must pass are examples of `spec/blargg/runner_spec.rb`, tagged `slow: true`: they run with `SLOW=1`
  and always in CI's `test-roms` job, under YJIT (plan 12, decision 6). The others are recorded here.

Only the NROM single-test builds run here. The multi-test builds (`all_instrs.nes`, `official_only.nes`,
`ppu_vbl_nmi.nes`, `cpu_interrupts.nes`) are MMC1 boards (plan 20), and `cpu_dummy_reads.nes` is CNROM (plan 19).

## Results

Plan 12, 2026-11-19. Frames are emulated frames until the result; times are under YJIT on the machine of
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
| `ppu_vbl_nmi/rom_singles/05-nmi_timing.nes` | Failed (1) | 220 | Prints `00 4`, `01-06 3`, `07-09 2`; not investigated (Known gaps: NMI suppression around VBlank). |
| `ppu_vbl_nmi/rom_singles/06-suppression.nes` | Failed (1) | 214 | Probably the reads on the dot VBlank starts or the next one, which do not suppress the NMI here (Known gaps); not investigated further. |
| `ppu_vbl_nmi/rom_singles/07-nmi_on_timing.nes` | Failed (1) | 194 | NMI taken for offsets `00-05`, not for `06-08`; not investigated. |
| `ppu_vbl_nmi/rom_singles/08-nmi_off_timing.nes` | Failed (1) | 237 | No NMI for offsets `03-04`, NMI for `05-0C`; not investigated. |
| `ppu_vbl_nmi/rom_singles/09-even_odd_frames.nes` | Passed | 71 | |
| `ppu_vbl_nmi/rom_singles/10-even_odd_timing.nes` | Failed (3) | 82 | "Clock is skipped too late, relative to enabling BG": rendering takes effect at once, not 3-4 dots later (Known gaps: rendering toggle delay). |
| `instr_misc/rom_singles/01-abs_x_wrap.nes` | Passed | 12 | |
| `instr_misc/rom_singles/02-branch_wrap.nes` | Passed | 11 | |
| `instr_misc/rom_singles/03-dummy_reads.nes` | Passed | 57 | Needs the indexed dummy reads (architecture decision 26). |
| `cpu_interrupts_v2/rom_singles/1-cli_latency.nes` | Failed (3) | 19 | "APU should generate IRQ when $4017 = $00": needs the APU frame IRQ (plan 22). |
| `cpu_interrupts_v2/rom_singles/2-nmi_and_brk.nes` | Failed (1) | 122 | An NMI during `BRK`: probably the hijacking, not modelled (plan 22). |
| `cpu_interrupts_v2/rom_singles/3-nmi_and_irq.nes` | Failed (1) | 139 | Needs the APU frame IRQ (plan 22). |
| `cpu_interrupts_v2/rom_singles/4-irq_and_dma.nes` | Failed (1) | 70 | Needs the APU frame IRQ (plan 22). |
| `cpu_interrupts_v2/rom_singles/5-branch_delays_irq.nes` | Timed out | 3600 | Stays at "test_jmp" waiting for an IRQ: needs the APU frame IRQ (plan 22). |
| `ppu_open_bus/ppu_open_bus.nes` | Failed (3) | 73 | "Decay value should become zero by one second": the I/O latch does not decay (plan 12, decision 9). |
