# frozen_string_literal: true

source 'https://rubygems.org'

# Specify your gem's dependencies in ruby-nes.gemspec
gemspec

group :development, :test do
  gem 'irb'
  gem 'rake', '>= 13.0'
  gem 'rspec', '~> 3.13'
  gem 'rubocop', require: false
  gem 'rubocop-rake', require: false
  gem 'rubocop-rspec', require: false
  gem 'rubocop-vicenzo', '~> 0.10.0', require: false
  gem 'simplecov', require: false
  # The sampling profiler of plan 25 (`rake bench:profile`).
  gem 'vernier', require: false
end

# The windowed backend chosen by plan 17 (raylib); the core never requires it. Install with
# `bundle config set --local with frontends`.
group :frontends, optional: true do
  gem 'raylib-bindings', '~> 0.8.4', require: false
end
