# Spinel: ruby-nes compiled ahead of time

Plan 26 compiled ruby-nes with [Spinel](https://github.com/matz/spinel), matz's ahead-of-time compiler: it parses the
whole program with Prism, infers its types, writes C and builds a native executable with the system's `cc`. The
question was how much of ruby-nes it compiles, what that costs in code changes, and how fast the result runs next to
CRuby with and without its JITs.

Measured on 2026-11-24: Spinel 2026.10.25 (revision 2814693f6) on Apple clang 17.0.0; CRuby 4.0.9 (2026-10-23
revision 3e93b23afc); an Intel Core i5-8257U Mac, macOS 15 (Darwin 24.6.0).

## How to reproduce

```sh
rake test_roms:fetch   # nestest, for the CPU workload
rake spinel:fetch      # downloads the 2026.10.25 release into tmp/spinel and builds it (about 2 minutes)
rake bench:spinel      # compiles spinel/cpu.rb and spinel/frames.rb, measures them on CRuby and compiled; appends the
                       # tables to docs/benchmarks.md (about 15 minutes)
```

The frame workload also needs a dump of your own Super Mario Bros. 3 cartridge at `roms/smb3.nes`, as `rake
bench:frames` does. `rake bench:spinel` runs every program with no JIT inherited from the environment (`RUBYOPT`,
`RUBY_YJIT_ENABLE`, `RUBY_ZJIT_ENABLE`), checks that each one reports the configuration it was meant to run under
(`CpuBenchmark::Configuration.current`, which names Spinel's binaries `spinel`), and writes the tables only once both
programs have run.

The programs in `spinel/` are plain Ruby that CRuby runs too, so every row of a table comes from the same source:

- `spinel/cpu.rb` checks the trace against the whole of `nestest.log`, then measures plan 10's CPU workload.
- `spinel/frames.rb` plays plan 25's Super Mario Bros. 3 workload and prints the frame and audio digests.

They reuse the benchmarks' workloads, sessions and measurements (`bench/`). They don't use `OptionParser`, the JIT
variants or the test ROM manifest, which Spinel can't compile in these programs (see below), so `rake bench:spinel`
passes the paths and the workload's size as arguments.

## Building Spinel

The release archive builds with `make` alone (`make deps` isn't needed: it carries libprism). It took about 2 minutes on
8 jobs. One trap: built inside another git work tree (here `tmp/spinel`, inside this repository), the Makefile asks git
for the revision before reading the archive's `.spinel-dist`, and `spinel --version` reports the enclosing repository's
commit (`unreleased (15882a5)`). `rake spinel:fetch` sets `GIT_CEILING_DIRECTORIES` so git stops at `tmp/`.

Compiling one of our programs takes 16-22 s and gives a binary of 1.4-1.7 MB, which needs only the system libraries.

## The supported subset, as found

Everything the emulator's core uses compiled with no change: classes and modules nested three deep,
`require_relative` over more than a hundred files, `Data.define` (with and without a block), `Struct`, the `it` block
parameter, endless methods, keyword arguments, the two-level `case` of the CPU's dispatch, frozen constant tables built
with `Array.new(n) { }`, `Array#pack`, `String#byteslice`/`bytes`, `File.binread`, `format`, `Process.clock_gettime`,
`Integer#anybits?`, and the standard library's `digest` (SHA-256), `yaml` (`YAML.safe_load` of the input script) and
`json`. Under Spinel, `RUBY_ENGINE` is `"spinel"` and `RUBY_DESCRIPTION` is
`spinel 4.0.7 (2026.10.25 revision 2814693f6) [x86_64-darwin]`.

## Code changes

None in `lib/`. The benchmarks' tooling changed so the programs of `spinel/` could reuse it without loading what Spinel
can't compile:

- `CpuBenchmark::Configuration.current` names an engine other than CRuby after itself (`spinel`), instead of calling it
  `interpreter`.
- The hash each benchmark prints moved out of its command line into `CpuBenchmark::Measurement` and
  `FrameBenchmark::Measurement`, so `bench/cpu.rb`, `bench/frame.rb` and `spinel/` print the same line.
- `CpuBenchmark::Error` and `::BrokenVariant` moved to `bench/cpu_benchmark/errors.rb`, so the workload loads without
  the test ROM harness and its HTTP downloader.

## Correctness

- **Stage A, the CPU alone:** the compiled `spinel/cpu.rb` matches all 8991 lines of `nestest.log`. Its output is
  byte for byte the same as CRuby's.
- **Stage B, the whole core, headless:** the compiled `spinel/frames.rb` plays 1500 frames of Super Mario Bros. 3 with
  audio and gives CRuby's digests: frame `f0903fbc59bf`, audio `10369a5b40df`. That holds with and without the type
  seeds, and under `--int-overflow=wrap`.

## Speed

From `rake bench:spinel` (docs/benchmarks.md, 2026-11-24):

| Configuration | CPU, nestest (emulated MHz) | Super Mario Bros. 3 (frames per second) | vs YJIT (frames) |
|---|---|---|---|
| interpreter | 1.92 | 18.0 | 0.28× |
| YJIT | 10.99 | 65.0 | 1× |
| ZJIT | 5.67 | 42.7 | 0.66× |
| Spinel | 8.42 | 95.3 | 1.47× |
| Spinel + RBS seeds | 16.69 | 160.9 | 2.48× |
| Spinel + RBS seeds, `--int-overflow=wrap` | 17.60 | 178.7 | 2.75× |

Out of the box, Spinel is faster than YJIT on the whole game but slower on the CPU alone. A sampling profile of the
compiled CPU benchmark (`spinel --profile`, macOS `sample`) explains it: about 45% of the samples were in `sp_poly_*`,
Spinel's boxed operations on values whose type it couldn't settle (`sp_poly_bitop`, `sp_poly_add`, `sp_poly_lt`...),
and `CpuBus#read` led the rest. `--warn-widen` and `--emit-rbs` show where the types widen:

- **The mapper hierarchy.** Six mappers meet in one slot of the CPU bus and of the PPU bus, so `Mappers::Base#cpu_read`
  takes untyped arguments and returns an untyped value. MMC1's `@registers` comes out as `Array[untyped]`.
- **The buses.** From there, the bus's `address`, `value` and `@data_bus` widen, and with them the CPU's registers
  (`@accumulator`, `@index_x`, `@index_y`) and the addressing modes: the whole instruction path takes the slow path.
- **Not the null object.** `CpuBus::Disconnected`, the default device of each bus slot, wasn't the cause: making the
  slots required keywords moved the CPU from 8.32 to 8.56 MHz (an earlier session than the table's, both builds
measured back to back).

**The fix is a file of type seeds, not a change to the code.** `spinel/sig/nes.rbs` holds 24 RBS signatures:

- the integer signatures of the devices' `cpu_read`/`cpu_write`;
- `CpuBus#read`/`write` and `PpuBus#read`/`write` with their nametables and palette RAM;
- the CPU registers and the data bus.

`spinel --rbs spinel/sig` pins those slots before inference. CRuby never reads the file, and Spinel refuses to compile
when a value it can see contradicts a seed. Three rounds of profiling took the game from 95 to 161 frames per second.

A fourth round seeded MMC3's own `ppu_read`/`ppu_write` and its A12 watcher: MMC3 overrides `Base`'s, so the `Base`
seeds don't hold for Super Mario Bros. 3's board, and `--warn-widen` still reports widened slots there. It measured no
change (166.5 frames per second against 166.5 and 165.2, interleaved, both with `--int-overflow=wrap`) and was left out.

The integers already wrap where the hardware does (every hot-path value is masked), so `--int-overflow=wrap` changes no
output and takes away the overflow checks: another 5-11%.

## Stage C: the window

`exe/ruby-nes` itself, with the raylib-bindings gem, compiles: Spinel bundles a package that implements the `ffi` gem's
API over libffi (`extend FFI::Library`, `attach_function` under names computed at run time, `FFI::Struct`), so the gem
needs no change. It took `-I <raylib-bindings>/lib` and `--defer-refusals` (below), and the window didn't open yet.
What stood in the way, in order:

| # | What | Where | Kind | Workaround |
|---|---|---|---|---|
| 1 | `hash.fetch(key) { ... }` with a block that reads a local of the method: "unsupported proc referencing an uncaptured outer variable (later slice)" | `CommandLine::Jit#enable`, and Spinel's own `optparse` package (`Switch#summarize`) | Spinel: refused in the whole program, but compiles in a 4-line program | `--defer-refusals`, so the statement raises `NotImplementedError` only when reached |
| 2 | `RubyVM` doesn't exist, and the `RubyVM.const_get` values `CommandLine::Jit::COMPILERS` stores in a Hash produce C that doesn't compile (`passing 'sp_RbVal' to parameter of incompatible type 'sp_int'`) | `CommandLine::Jit` | Spinel: miscompile; not reproduced in a small program | An empty `module RubyVM; end` in the entry point: the table comes out empty |
| 3 | `OptionParser#on('--jit NAME', %w[none yjit zjit])` raises `argument type given twice` | `CommandLine::Options` | Spinel's `optparse` package diverges from CRuby in the whole program; a small program parses it right | Build `CommandLine::Options` (a `Data`) directly in the entry point, with no `OptionParser` |
| 4 | `require library`, with `library` a constant built by `File.expand_path`, isn't resolved at compile time and raises `LoadError` when it runs | `CommandLine::RaylibWindow` | Spinel: reproduced in 3 lines (below) | `require_relative` the frontend in the entry point first |
| 5 | `Kernel.method(:sleep)` is refused: "a Method object of a builtin module or class function has no compiled function to bind" | `Frontends::FramePacing`, `Frontends::AudioPacing` | Documented limitation | `->(seconds) { sleep(seconds) }`, a change to `lib/` |
| 6 | `Gem::Specification` doesn't exist in a binary | `Frontends::Raylib.load_library` | Expected: there are no gems at run time | Let the entry point pass the library's path, a change to `lib/` |
| 7 | `@source.width` in `Frontends::Viewport`: "undefined method 'width' for a Class", `@source` being a `Viewport::Rectangle` (a `Data`) | `Frontends::Viewport` | Spinel: inference; neither a small program nor a name clash with `Raylib::Rectangle` reproduces it, and an RBS seed for `@source` didn't help | None yet |

Plan 26 closes with stages A and B, and no `bin/ruby-nes`: the window waits for Spinel to mature. What was left to
find out after 7, besides the changes to `lib/` (5 and 6): FFI structs passed by value (`Texture2D`, `Shader`,
`AudioStream`), the palette shader, and the audio stream.

### Reproductions for the Spinel issue tracker

Not filed: drafts for the user to decide on.

**A constant built by `File.expand_path` doesn't resolve a `require`** (Spinel 2026.10.25; the release notes say
"computed requires ... resolved from each file's own parse tree"):

```ruby
# helper.rb
module Helper
  def self.answer = 42
end

# main.rb
LIBRARY = File.expand_path('helper', __dir__)
require LIBRARY
puts Helper.answer
```

CRuby prints `42`. `spinel -E main.rb` refuses `main.rb:3: unsupported puts argument: node 13 (CallNode 'answer')
recv=ConstantReadNode/ty0`, and in a larger program, where the constant is read inside a method, it compiles and
raises `LoadError` when the `require` runs.

**Whole-program-only failures (1, 2, 3 and 7 above).** Each compiles and runs right in a small program. They
reproduce with this repository at the plan 26 commit:

```sh
spinel exe/ruby-nes -I "$(dirname "$(gem which raylib)")" --rbs spinel/sig
```

**Building inside another git work tree stamps that tree's revision** (`spinel --version` gives
`unreleased (<the enclosing repository's commit>)`): `build/csrc/spinel_rev.h` asks `git rev-parse` before it reads
`.spinel-dist`.

## Other findings

- **`bench/frame.rb` compiles but fails when it starts.** Through `bench/cpu_benchmark.rb` it loads the test ROM
  downloader, whose `TRANSFER_FAILURES` list names `Net::HTTPBadResponse` and `Net::HTTPHeaderSyntaxError`, which
  Spinel's `net/http` package doesn't define: the constant raises `NameError` when the file loads. Spinel also warned
  that "type inference did not converge in 128 rounds" on that program. That is why `spinel/` has entry points of its
  own.
- **Spinel can build CRuby extensions too** (`--ext cruby`, `--ext-entry`): an AOT-compiled core loaded by CRuby, the
  window staying on CRuby. Not tried.
- **Compile-time warnings name every constant defined nowhere** (`RubyVM::YJIT`, `RubyVM::ZJIT`). That is useful for
  spotting code a binary would reach and fail on.

## Conclusion

**Can ruby-nes be compiled with Spinel and played? Not yet.** The emulation compiles and runs; the window it is played
in does not.

- **What works.** Spinel compiled the emulation core as it is: CPU, PPU, APU, six mappers, the audio pipeline, the
  YAML input script and the digests, with no change to `lib/`. The binaries give exactly CRuby's results: the nestest
  trace, and Super Mario Bros. 3's frame and audio digests. They are fast:
  - Out of the box they run the game 1.5 times as fast as YJIT.
  - With 24 RBS signatures that pin the types the mapper hierarchy and the bus slots blur, and with integers that
    wrap, they run it 2.75 times as fast (179 frames per second against 65), and the CPU alone 1.6 times as fast.
- **What doesn't.** The window, the keyboard, the speaker and the command line around the core. They lean on the
  standard library and on dynamic Ruby (`OptionParser`, `RubyVM`, `Gem`, computed requires, `Method` objects). They
  compile only with refusals deferred, and the window doesn't open: Spinel bugs stand in the way, one of them (in
  `Frontends::Viewport`) with no workaround found. Playing would also need:
  - those bugs fixed or worked around;
  - two small changes to `lib/`;
  - an entry point that builds the options and loads raylib by path.

  There is no `bin/ruby-nes`. That waits for Spinel to mature.

The core's design rules (explicit requires, no metaprogramming, integers and preallocated arrays on hot paths) were
what made it compile. The polymorphic slots (mappers, bus devices) are what cost Spinel its speed, and a type seed
recovers it without touching the code.

YJIT stays the emulator's runtime: it needs no build step and no type seeds, it already plays at full speed, and it
runs the window. Spinel is the fastest way to run the same emulation, at the price of a compile step and of checking,
by digest, that the binary still matches CRuby.
