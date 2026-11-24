<h1 align="center"><img src="docs/logo.svg" alt="ruby-nes" width="700"></h1>

A Nintendo Entertainment System emulator written in pure Ruby 4 — a study project.

It explores two things at once: how the NES works (6502 CPU, PPU, APU, cartridge mappers) and how far modern Ruby
can go on a tight emulation loop (interpreter vs YJIT vs ZJIT, plus an ahead-of-time compilation experiment).

## Status

Early setup. The roadmap lives in [`plans/`](plans/README.md).

## Requirements

- Ruby 4.0.9 (`mise install` picks it up from `mise.toml`)
- Bundler

## Development

```bash
bin/setup                      # install dependencies
bundle exec rspec              # run the tests
COVERAGE=1 bundle exec rspec   # with branch coverage
bundle exec rubocop            # lint
bundle exec rake               # tests + lint
```

ROM images are not distributed with this project. Use dumps of cartridges you own.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
