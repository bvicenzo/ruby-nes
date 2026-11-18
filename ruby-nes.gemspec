# frozen_string_literal: true

require_relative 'lib/ruby/nes/version'

Gem::Specification.new do |spec|
  spec.name = 'ruby-nes'
  spec.version = Ruby::Nes::VERSION
  spec.authors = ['Bruno Vicenzo']
  spec.email = ['bruno@alumni.usp.br']

  spec.summary = 'A Nintendo Entertainment System emulator written in modern Ruby.'
  spec.description = <<~TEXT.tr("\n", ' ').strip
    A study project: an NES emulator (6502 CPU, PPU, APU and cartridge mappers) written in pure Ruby,
    used to explore Ruby 4 performance features such as YJIT, ZJIT and ahead-of-time compilation.
  TEXT
  spec.license = 'GPL-3.0-or-later'
  spec.required_ruby_version = '>= 4.0.0'
  spec.metadata['rubygems_mfa_required'] = 'true'

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  development_files = %w[bin/ Gemfile .gitignore .rspec spec/ .rubocop.yml plans/ CLAUDE.md .github/ rakelib/ bench/]
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |listing|
    listing.readlines("\x0", chomp: true).reject do |file|
      (file == gemspec) || file.start_with?(*development_files)
    end
  end
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |file| File.basename(file) }
  spec.require_paths = ['lib']
end
