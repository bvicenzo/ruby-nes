# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require_relative 'support/test_roms/sandboxed_group'

RSpec.describe LocalRoms do
  describe '.install' do
    let(:directory) { Dir.mktmpdir }
    let(:install_hook) { ->(config) { described_class.install(config, directory:) } }

    after { FileUtils.remove_entry(directory) }

    context 'when nothing declares a local ROM' do
      subject(:sandboxed_run) { TestRoms::SandboxedGroup.run(&install_hook) }

      it { expect(sandboxed_run.execution_result.status).to eq(:passed) }
    end

    context 'when a group declares a local ROM' do
      let(:group_metadata) { [{ local_rom: 'smb3.nes' }] }

      context 'but the file is absent' do
        subject(:sandboxed_run) { TestRoms::SandboxedGroup.run(group_metadata:, group_hook_body:, &install_hook) }

        let(:group_hook_body) { -> { raise 'the group hook ran' } }

        it 'skips the group before its own hooks run, naming the path' do
          absent_rom_path = File.join(directory, 'smb3.nes')

          expect(sandboxed_run.execution_result)
            .to have_attributes(status: :pending, pending_message: a_string_including(absent_rom_path))
        end
      end

      context 'and the file is present' do
        subject(:sandboxed_run) { TestRoms::SandboxedGroup.run(group_metadata:, &install_hook) }

        before { File.binwrite(File.join(directory, 'smb3.nes'), 'NES') }

        it { expect(sandboxed_run.execution_result.status).to eq(:passed) }
      end
    end

    context 'when a group declares several local ROMs' do
      subject(:sandboxed_run) { TestRoms::SandboxedGroup.run(group_metadata:, &install_hook) }

      let(:group_metadata) { [{ local_rom: %w[smb1.nes smb3.nes] }] }

      context 'but one of them is absent' do
        before { File.binwrite(File.join(directory, 'smb3.nes'), 'NES') }

        it 'skips the group, naming the absent one' do
          absent_rom_path = File.join(directory, 'smb1.nes')

          expect(sandboxed_run.execution_result)
            .to have_attributes(status: :pending, pending_message: a_string_including(absent_rom_path))
        end
      end

      context 'and all of them are present' do
        before do
          File.binwrite(File.join(directory, 'smb1.nes'), 'NES')
          File.binwrite(File.join(directory, 'smb3.nes'), 'NES')
        end

        it { expect(sandboxed_run.execution_result.status).to eq(:passed) }
      end
    end

    context 'when an example declares a local ROM' do
      let(:example_metadata) { { local_rom: 'smb3.nes' } }

      context 'but the file is absent' do
        subject(:sandboxed_run) { TestRoms::SandboxedGroup.run(example_metadata:, &install_hook) }

        it 'skips the example, naming the path' do
          absent_rom_path = File.join(directory, 'smb3.nes')

          expect(sandboxed_run.execution_result)
            .to have_attributes(status: :pending, pending_message: a_string_including(absent_rom_path))
        end
      end

      context 'and the file is present' do
        subject(:sandboxed_run) { TestRoms::SandboxedGroup.run(example_metadata:, &install_hook) }

        before { File.binwrite(File.join(directory, 'smb3.nes'), 'NES') }

        it { expect(sandboxed_run.execution_result.status).to eq(:passed) }
      end
    end
  end

  describe '#local_rom_path' do
    let(:directory) { Dir.mktmpdir }
    let(:install_hook) { ->(config) { described_class.install(config, directory:) } }
    let(:group_metadata) { [{ local_rom: 'smb3.nes' }] }
    let(:read_rom_path) { -> { local_rom_path('smb3.nes') } }

    before { File.binwrite(File.join(directory, 'smb3.nes'), 'NES') }

    after { FileUtils.remove_entry(directory) }

    context 'when the name was not declared' do
      subject(:sandboxed_run) do
        TestRoms::SandboxedGroup.run(group_metadata:, example_body: -> { local_rom_path('smb1.nes') }, &install_hook)
      end

      it 'fails the example with an UndeclaredRomError naming it' do
        undeclared_rom_error = an_instance_of(LocalRoms::UndeclaredRomError)
          .and(having_attributes(message: /smb1\.nes/))

        expect(sandboxed_run.execution_result).to have_attributes(status: :failed, exception: undeclared_rom_error)
      end
    end

    context 'when the name was declared' do
      context 'and it is read inside an example' do
        subject(:sandboxed_run) do
          TestRoms::SandboxedGroup.run(group_metadata:, example_body: read_rom_path, &install_hook)
        end

        it { expect(sandboxed_run.example_value).to eq(File.join(directory, 'smb3.nes')) }
      end

      context 'and it is read inside a group hook' do
        subject(:sandboxed_run) do
          TestRoms::SandboxedGroup.run(group_metadata:, group_hook_body: read_rom_path, &install_hook)
        end

        it { expect(sandboxed_run.group_hook_value).to eq(File.join(directory, 'smb3.nes')) }
      end
    end
  end
end
