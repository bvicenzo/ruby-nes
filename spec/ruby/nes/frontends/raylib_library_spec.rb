# frozen_string_literal: true

require 'ruby/nes/frontends/raylib_library'

# The raylib library each platform build of the raylib-bindings gem ships in its lib/ directory (plan 17): named by
# processor on macOS and Linux (libraylib.x86_64.dylib, libraylib.aarch64.so), and libraylib.dll on Windows.
RSpec.describe Ruby::Nes::Frontends::RaylibLibrary do
  describe '.path' do
    context 'when the system is macOS' do
      it "is the gem's library for the processor, as a dylib" do
        expect(described_class.path(gem_directory: '/gems/raylib', host_os: 'darwin24', host_cpu: 'arm64'))
          .to eq('/gems/raylib/lib/libraylib.arm64.dylib')
      end
    end

    context 'when the system is Linux' do
      it "is the gem's library for the processor, as a shared object" do
        expect(described_class.path(gem_directory: '/gems/raylib', host_os: 'linux-gnu', host_cpu: 'x86_64'))
          .to eq('/gems/raylib/lib/libraylib.x86_64.so')
      end
    end

    context 'when the system is Windows' do
      it "is the gem's libraylib.dll, whatever the processor" do
        expect(described_class.path(gem_directory: 'C:/gems/raylib', host_os: 'mingw32', host_cpu: 'x64'))
          .to eq('C:/gems/raylib/lib/libraylib.dll')
      end
    end

    context 'when the system is another one' do
      it 'raises LoadError naming it' do
        expect { described_class.path(gem_directory: '/gems/raylib', host_os: 'freebsd14', host_cpu: 'amd64') }
          .to raise_error(LoadError, /freebsd14/)
      end
    end
  end
end
