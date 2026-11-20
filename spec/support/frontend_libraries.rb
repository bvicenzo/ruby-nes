# frozen_string_literal: true

# The windowed backends of plan 17 need gems of the optional `frontends` Gemfile group, never installed in CI. A group
# that tests one declares the file to load with `frontend_library:`, and the group is skipped, before its own hooks
# run, when that file cannot be loaded:
#
#   RSpec.describe 'Ruby::Nes::Frontends::Raylib', frontend_library: 'ruby/nes/frontends/raylib' do
module FrontendLibraries
  INSTALL_HINT = 'install the optional frontends group: bundle config set --local with frontends'

  def self.install(config)
    config.before(:context, :frontend_library) do
      reason = FrontendLibraries.skip_reason(self.class.metadata[:frontend_library])
      skip(reason) if reason
    end
  end

  # Nil when the file loads; otherwise why the group is skipped.
  def self.skip_reason(path)
    require path
    nil
  rescue LoadError => error
    "#{error.message} (#{INSTALL_HINT})"
  end
end
