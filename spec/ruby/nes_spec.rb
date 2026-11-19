# frozen_string_literal: true

require 'open3'

# The core never depends on a frontend (docs/architecture.md, Frame buffer contract; plan 16): `require 'ruby/nes'`
# loads the emulator alone. Checked in a process of its own, since this one has loaded the frontends for their specs;
# the process prints the frontend and command line files it loaded, then whether Ruby::Nes::Frontends exists (a load
# error would be printed instead).
RSpec.describe Ruby::Nes do
  describe 'loading the core' do
    subject(:loading_report) do
      script = <<~RUBY
        require 'ruby/nes'
        puts $LOADED_FEATURES.grep(%r{/ruby/nes/(frontends/|command_line)})
        puts Ruby::Nes.const_defined?(:Frontends, false)
      RUBY
      Open3.capture2e(RbConfig.ruby, '-I', File.expand_path('../../lib', __dir__), '-e', script).first
    end

    it 'loads no frontend and no command line' do
      expect(loading_report).to eq("false\n")
    end
  end
end
