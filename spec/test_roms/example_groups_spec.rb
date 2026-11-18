# frozen_string_literal: true

require_relative '../support/test_roms/sandboxed_group'

RSpec.describe TestRoms::ExampleGroups do
  describe '.install' do
    let(:requirement) { instance_double(TestRoms::Requirement) }
    let(:install_hook) { ->(config) { described_class.install(config, requirement:) } }

    context 'when nothing declares a test ROM' do
      subject(:sandboxed_run) { TestRoms::SandboxedGroup.run(&install_hook) }

      before do
        allow(requirement).to receive(:ensure_listed)
        allow(requirement).to receive(:skip_reason)
      end

      it 'runs the example without consulting the requirement', :aggregate_failures do
        expect(sandboxed_run.execution_result.status).to eq(:passed)
        expect(requirement).not_to have_received(:ensure_listed)
        expect(requirement).not_to have_received(:skip_reason)
      end
    end

    context 'when a group declares a test ROM' do
      context 'but the manifest does not list it' do
        subject(:sandboxed_run) { TestRoms::SandboxedGroup.run(group_metadata:, &install_hook) }

        let(:group_metadata) { [{ test_rom: 'other/nestset.nes' }] }

        before do
          allow(requirement)
            .to receive(:ensure_listed)
            .with(['other/nestset.nes'])
            .and_raise(TestRoms::UnknownRomError, 'other/nestset.nes')
        end

        it { expect { sandboxed_run }.to raise_error(TestRoms::UnknownRomError, 'other/nestset.nes') }
      end

      context 'and the manifest lists it' do
        let(:group_metadata) { [{ test_rom: 'other/nestest.nes' }] }

        before { allow(requirement).to receive(:ensure_listed).with(['other/nestest.nes']) }

        context 'but it is missing' do
          subject(:sandboxed_run) { TestRoms::SandboxedGroup.run(group_metadata:, group_hook_body:, &install_hook) }

          let(:reason) { 'Test ROMs missing or corrupted (other/nestest.nes): run `bundle exec rake test_roms:fetch`' }
          let(:group_hook_body) { -> { raise 'the group hook ran' } }

          before { allow(requirement).to receive(:skip_reason).with(['other/nestest.nes']).and_return(reason) }

          it 'skips the group before its own hooks run' do
            expect(sandboxed_run.execution_result).to have_attributes(status: :pending, pending_message: reason)
          end
        end

        context 'and it is intact' do
          subject(:sandboxed_run) { TestRoms::SandboxedGroup.run(group_metadata:, &install_hook) }

          before { allow(requirement).to receive(:skip_reason).with(['other/nestest.nes']).and_return(nil) }

          it { expect(sandboxed_run.execution_result.status).to eq(:passed) }
        end
      end
    end

    context 'when an example declares a test ROM' do
      context 'but the manifest does not list it' do
        subject(:sandboxed_run) { TestRoms::SandboxedGroup.run(example_metadata:, &install_hook) }

        let(:example_metadata) { { test_rom: 'other/nestset.nes' } }

        before do
          allow(requirement)
            .to receive(:ensure_listed)
            .with(['other/nestset.nes'])
            .and_raise(TestRoms::UnknownRomError, 'other/nestset.nes')
        end

        it { expect { sandboxed_run }.to raise_error(TestRoms::UnknownRomError, 'other/nestset.nes') }
      end

      context 'and the manifest lists it' do
        let(:example_metadata) { { test_rom: 'other/nestest.nes' } }

        before do
          allow(requirement).to receive(:ensure_listed).with(['other/nestest.nes'])
          # The group around the example declares nothing, so its own check finds no ROM to require.
          allow(requirement).to receive(:skip_reason).with([]).and_return(nil)
        end

        context 'but it is missing' do
          subject(:sandboxed_run) { TestRoms::SandboxedGroup.run(example_metadata:, &install_hook) }

          let(:reason) { 'Test ROMs missing or corrupted (other/nestest.nes): run `bundle exec rake test_roms:fetch`' }

          before { allow(requirement).to receive(:skip_reason).with(['other/nestest.nes']).and_return(reason) }

          it { expect(sandboxed_run.execution_result).to have_attributes(status: :pending, pending_message: reason) }
        end

        context 'and it is intact' do
          subject(:sandboxed_run) { TestRoms::SandboxedGroup.run(example_metadata:, &install_hook) }

          before { allow(requirement).to receive(:skip_reason).with(['other/nestest.nes']).and_return(nil) }

          it { expect(sandboxed_run.execution_result.status).to eq(:passed) }
        end
      end
    end

    context 'when test ROMs are declared at several levels' do
      subject(:sandboxed_run) { TestRoms::SandboxedGroup.run(group_metadata:, example_metadata:, &install_hook) }

      let(:group_metadata) do
        [{ test_rom: %w[other/nestest.nes other/nestest.log] }, {}, { test_rom: 'cpu/official.nes' }]
      end
      let(:example_metadata) { { test_rom: 'cpu/timing.nes' } }
      let(:every_declared_rom) do
        contain_exactly('other/nestest.nes', 'other/nestest.log', 'cpu/official.nes', 'cpu/timing.nes')
      end

      before do
        allow(requirement).to receive(:ensure_listed)
        allow(requirement).to receive(:skip_reason).and_return(nil)
      end

      it 'requires all of them for the example', :aggregate_failures do
        expect(sandboxed_run.execution_result.status).to eq(:passed)
        expect(requirement).to have_received(:skip_reason).with(every_declared_rom)
      end
    end
  end

  describe '#test_rom_path' do
    context 'when the hook is installed in a sandbox with a stand-in requirement' do
      let(:requirement) { instance_double(TestRoms::Requirement) }
      let(:install_hook) { ->(config) { described_class.install(config, requirement:) } }

      before do
        allow(requirement).to receive(:ensure_listed)
        allow(requirement).to receive(:skip_reason).and_return(nil)
        allow(requirement).to receive(:path_of).with('other/nestest.nes').and_return('/fixtures/other/nestest.nes')
      end

      context 'but the path was not declared' do
        subject(:sandboxed_run) do
          TestRoms::SandboxedGroup.run(group_metadata:, example_body:, &install_hook)
        end

        let(:group_metadata) { [{ test_rom: 'other/nestest.nes' }] }
        let(:example_body) { -> { test_rom_path('other/nestest.log') } }

        it 'fails the example with an UndeclaredRomError naming the path' do
          undeclared_rom_error = an_instance_of(TestRoms::UndeclaredRomError)
            .and(having_attributes(message: /nestest\.log/))

          expect(sandboxed_run.execution_result).to have_attributes(status: :failed, exception: undeclared_rom_error)
        end
      end

      context 'and the path was declared on the example' do
        subject(:sandboxed_run) do
          TestRoms::SandboxedGroup
            .run(example_metadata: { test_rom: 'other/nestest.nes' }, example_body: read_rom_path, &install_hook)
        end

        let(:read_rom_path) { -> { test_rom_path('other/nestest.nes') } }

        it { expect(sandboxed_run.example_value).to eq('/fixtures/other/nestest.nes') }
      end

      context 'and the path was declared on a group' do
        let(:group_metadata) { [{ test_rom: 'other/nestest.nes' }] }
        let(:read_rom_path) { -> { test_rom_path('other/nestest.nes') } }

        context 'and it is read inside an example' do
          subject(:sandboxed_run) do
            TestRoms::SandboxedGroup.run(group_metadata:, example_body: read_rom_path, &install_hook)
          end

          it { expect(sandboxed_run.example_value).to eq('/fixtures/other/nestest.nes') }
        end

        context 'and it is read inside a group hook' do
          subject(:sandboxed_run) do
            TestRoms::SandboxedGroup.run(group_metadata:, group_hook_body: read_rom_path, &install_hook)
          end

          it { expect(sandboxed_run.group_hook_value).to eq('/fixtures/other/nestest.nes') }
        end
      end
    end

    # The suite's real manifest and fetched files: the group runs only after `rake test_roms:fetch`.
    context 'when the hook is the one the suite installs', test_rom: 'other/nestest.nes' do
      # Size of other/nestest.nes at the pinned commit, as listed by https://github.com/christopherpow/nes-test-roms.
      it 'gives the path of the fetched file' do
        expect(File.size(test_rom_path('other/nestest.nes'))).to eq(24_592)
      end
    end
  end
end
