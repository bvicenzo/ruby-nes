# frozen_string_literal: true

require 'ruby/nes/command_line'

# The window CommandLine::Window opens by default (plan 18): raylib, loaded only when a window is asked for, since its
# gem is in the optional `frontends` Gemfile group (plan 17, decision 5).
RSpec.describe Ruby::Nes::CommandLine::RaylibWindow do
  describe '.call' do
    let(:keys) { Ruby::Nes::Frontends::KeyConfig.new({}).keys }
    let(:viewport) { Ruby::Nes::Frontends::Viewport.new(scale: 1, pixel_aspect: 1, crop_overscan: true) }

    context 'when the window library cannot be loaded' do
      let(:library) { 'ruby/nes/frontends/absent_backend' }

      it 'raises an Error naming how to install it' do
        expect { described_class.call(keys:, viewport:, jit_name: 'yjit', library:) }
          .to raise_error(Ruby::Nes::Error, /absent_backend.*bundle config set --local with frontends/)
      end
    end

    context 'when the window library loads', frontend_library: 'ruby/nes/frontends/raylib' do
      it 'opens a raylib window' do
        frontend = described_class.call(keys:, viewport:, jit_name: 'yjit', hidden: true)
        expect(frontend).to be_a(Ruby::Nes::Frontends::Raylib)
      ensure
        frontend&.close
      end
    end
  end
end
