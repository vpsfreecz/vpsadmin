# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'nodectld/commands/base'
require 'nodectld/commands/dataset/remove_download'

RSpec.describe NodeCtld::Commands::Dataset::RemoveDownload do
  let(:driver) { build_storage_driver }
  let(:tmpdir) { Dir.mktmpdir('remove-download-spec') }
  let(:pool_fs) { File.join(tmpdir, 'tank').sub(%r{^/}, '') }
  let(:cmd) do
    described_class.new(
      driver,
      'pool_fs' => pool_fs,
      'secret_key' => 'secret',
      'file_name' => 'download.dat.gz'
    )
  end

  before do
    $CFG = NodeCtldSpec::FakeCfg.new(
      bin: {
        rm: 'rm',
        rmdir: 'rmdir'
      }
    )
  end

  after do
    FileUtils.rm_rf(tmpdir)
  end

  it 'removes the download file and its secret directory when present' do
    FileUtils.mkdir_p(cmd.send(:secret_dir_path))
    File.write(cmd.send(:file_path), 'payload')

    expect(cmd.exec).to eq(ret: :ok)
    expect(File.exist?(cmd.send(:file_path))).to be(false)
    expect(Dir.exist?(cmd.send(:secret_dir_path))).to be(false)
  end

  it 'removes the secret directory when the file is already gone' do
    FileUtils.mkdir_p(cmd.send(:secret_dir_path))

    expect(cmd.exec).to eq(ret: :ok)
    expect(Dir.exist?(cmd.send(:secret_dir_path))).to be(false)
  end

  it 'is idempotent and does not shell out when nothing exists' do
    allow(cmd).to receive(:syscmd)
    expect(cmd.exec).to eq(ret: :ok)
    expect(cmd).not_to have_received(:syscmd)
  end
end
