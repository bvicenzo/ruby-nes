# frozen_string_literal: true

require 'ruby/nes/command_line'

# The JIT the command line runs the emulator under (plan 18, decisions 1 and 8): `--jit=none|yjit|zjit`, enabled at
# runtime, which Ruby 4.0.9 allows for both YJIT and ZJIT. Ruby runs one JIT at a time and cannot turn one off, so a
# JIT already running (from RUBYOPT or a flag) that differs from the one asked is an error, never a silent change. The
# compilers are injected: here doubles with the interface of RubyVM::YJIT, which RubyVM::ZJIT shares (a Ruby built
# without ZJIT has no RubyVM::ZJIT to verify against).
RSpec.describe Ruby::Nes::CommandLine::Jit do
  describe '#enable' do
    context 'when no JIT is asked' do
      context 'but a JIT is already running' do
        subject(:jit) { described_class.new({ 'yjit' => yjit }) }

        let(:yjit) { class_double(RubyVM::YJIT, enabled?: true) }

        it 'raises Unavailable naming it' do
          expect { jit.enable('none') }.to raise_error(described_class::Unavailable, /yjit is already running/)
        end
      end

      context 'and none is running' do
        subject(:jit) { described_class.new({ 'yjit' => yjit }) }

        let(:yjit) { class_double(RubyVM::YJIT, enabled?: false, enable: true) }

        before { jit.enable('none') }

        it 'enables nothing' do
          expect(yjit).not_to have_received(:enable)
        end
      end
    end

    context 'when a JIT is asked' do
      context 'but this Ruby does not have it' do
        subject(:jit) { described_class.new({ 'yjit' => yjit }) }

        let(:yjit) { class_double(RubyVM::YJIT, enabled?: false) }

        it 'raises Unavailable naming it' do
          expect { jit.enable('zjit') }.to raise_error(described_class::Unavailable, /zjit/)
        end
      end

      context 'and this Ruby has it' do
        context 'but another JIT is already running' do
          subject(:jit) { described_class.new({ 'yjit' => yjit, 'zjit' => zjit }) }

          let(:yjit) { class_double(RubyVM::YJIT, enabled?: true) }
          let(:zjit) { class_double(RubyVM::YJIT, enabled?: false) }

          it 'raises Unavailable naming both' do
            expect { jit.enable('zjit') }.to raise_error(described_class::Unavailable, /yjit .*zjit/)
          end
        end

        context 'and it is already running' do
          subject(:jit) { described_class.new({ 'yjit' => yjit, 'zjit' => zjit }) }

          let(:yjit) { class_double(RubyVM::YJIT, enabled?: false) }
          let(:zjit) { class_double(RubyVM::YJIT, enabled?: true, enable: true) }

          before { jit.enable('zjit') }

          it 'enables nothing' do
            expect(zjit).not_to have_received(:enable)
          end
        end

        context 'and no JIT is running' do
          context 'but enabling it fails' do
            subject(:jit) { described_class.new({ 'yjit' => yjit, 'zjit' => zjit }) }

            let(:yjit) { class_double(RubyVM::YJIT, enabled?: false, enable: false) }
            let(:zjit) { class_double(RubyVM::YJIT, enabled?: false) }

            it 'raises Unavailable naming it' do
              expect { jit.enable('yjit') }.to raise_error(described_class::Unavailable, /yjit/)
            end
          end

          context 'and it enables' do
            subject(:jit) { described_class.new({ 'yjit' => yjit, 'zjit' => zjit }) }

            let(:yjit) { class_double(RubyVM::YJIT, enabled?: false, enable: true) }
            let(:zjit) { class_double(RubyVM::YJIT, enabled?: false) }

            before { jit.enable('yjit') }

            it 'enables it' do
              expect(yjit).to have_received(:enable)
            end
          end
        end
      end
    end
  end

  describe '#running' do
    context 'when no JIT is running' do
      subject(:jit) { described_class.new({ 'yjit' => yjit, 'zjit' => zjit }) }

      let(:yjit) { class_double(RubyVM::YJIT, enabled?: false) }
      let(:zjit) { class_double(RubyVM::YJIT, enabled?: false) }

      it 'is none' do
        expect(jit.running).to eq('none')
      end
    end

    context 'when a JIT is running' do
      subject(:jit) { described_class.new({ 'yjit' => yjit, 'zjit' => zjit }) }

      let(:yjit) { class_double(RubyVM::YJIT, enabled?: false) }
      let(:zjit) { class_double(RubyVM::YJIT, enabled?: true) }

      it 'is its name' do
        expect(jit.running).to eq('zjit')
      end
    end
  end
end
