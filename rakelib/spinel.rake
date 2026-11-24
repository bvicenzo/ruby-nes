# frozen_string_literal: true

# The Spinel AOT experiment (plans/26-spinel-experiment.md): a pinned Spinel release built under tmp/, which
# `rake bench:spinel` compiles the programs of spinel/ with. Nothing here runs in CI (plan 26, out of scope).
namespace :spinel do
  root = File.expand_path('..', __dir__)
  # The release the experiment was run with (plan 26, decision 4): dated tags, https://github.com/matz/spinel/releases.
  release = '2026.10.25'
  spinel_directory = File.join(root, 'tmp', 'spinel')
  compiler = File.join(spinel_directory, 'bin', 'spinel')

  desc "Download Spinel #{release} into tmp/spinel and build it (about 2 minutes)"
  task :fetch do
    require 'tmpdir'

    archive = "spinel-#{release}.tar.xz"
    url = "https://github.com/matz/spinel/releases/download/#{release}/#{archive}"
    Dir.mktmpdir do |download_directory|
      download = File.join(download_directory, archive)
      sh 'curl', '--fail', '--silent', '--show-error', '--location', '--output', download, url
      sh 'tar', '-xJf', download, '-C', download_directory
      FileUtils.rm_rf(spinel_directory)
      FileUtils.mv(File.join(download_directory, "spinel-#{release}"), spinel_directory)
    end
    # The release archive records its revision in .spinel-dist, but the build asks git first, which would answer with
    # this repository's commit: the ceiling stops git from looking above tmp/spinel.
    sh({ 'GIT_CEILING_DIRECTORIES' => File.dirname(spinel_directory) }, 'make', '-C', spinel_directory, '-j8')
    sh compiler, '--version'
  end
end
