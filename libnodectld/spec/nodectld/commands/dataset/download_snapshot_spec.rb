# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'pathname'
require 'nodectld/commands/base'
require 'nodectld/commands/dataset/download_snapshot'
require 'nodectld/zfs_stream'

RSpec.describe NodeCtld::Commands::Dataset::DownloadSnapshot do
  let(:driver) do
    instance_double(
      NodeCtld::Command,
      id: 123,
      progress: nil,
      'progress=': nil,
      log_type: :spec
    )
  end

  let(:tmpdir) { Dir.mktmpdir('download-snapshot-spec') }
  let(:pool_fs) { File.join(tmpdir, 'tank').sub(%r{^/}, '') }

  after do
    FileUtils.rm_rf(tmpdir)
  end

  def build_command(file_name:, format:, from_snapshot: nil)
    described_class.new(
      driver,
      'pool_fs' => pool_fs,
      'dataset_name' => 'user.dataset',
      'snapshot' => 'snap-2',
      'from_snapshot' => from_snapshot,
      'secret_key' => 'secret',
      'file_name' => file_name,
      'format' => format,
      'download_id' => 77
    )
  end

  it 'updates approximate size first, writes an archive, persists checksum metadata, and rolls back cleanly' do
    db = instance_spy(NodeCtld::Db)
    cmd = build_command(file_name: 'download.tar.gz', format: 'archive')
    mount_dir = cmd.send(:pool_mounted_download, pool_fs, '77')

    allow(NodeCtld::Db).to receive(:new).and_return(db)
    allow(cmd).to receive(:zfs).with(
      :get,
      '-Hp -o value referenced',
      "#{pool_fs}/user.dataset@snap-2"
    ).and_return(double(output: (20 * 1024 * 1024).to_s))
    allow(Pathname).to receive(:new).with(mount_dir).and_return(
      instance_double(Pathname, mountpoint?: false)
    )
    allow(db).to receive(:prepared).with(
      'UPDATE snapshot_downloads SET size = ? WHERE id = ?',
      20,
      77
    )
    allow(db).to receive(:close)
    allow(cmd).to receive(:syscmd).with(
      "mount -t zfs #{pool_fs}/user.dataset@snap-2 \"#{mount_dir}\""
    ).and_return(double(exitstatus: 0))
    allow(cmd).to receive(:pipe_cmd).with(
      "tar -cz -C \"#{mount_dir}\" ."
    ) do
      FileUtils.mkdir_p(cmd.send(:secret_dir_path))
      File.binwrite(cmd.send(:file_path), 'x' * (3 * 1024 * 1024))
      cmd.instance_variable_set(:@sum, 'archive-sum')
    end
    allow(cmd).to receive(:syscmd).with(
      "umount \"#{mount_dir}\"",
      valid_rcs: [32]
    ).and_return(double(exitstatus: 0))

    expect(cmd.exec).to eq(ret: :ok)
    expect(File.exist?(cmd.send(:file_path))).to be(true)
    expect(db).to have_received(:prepared).with(
      'UPDATE snapshot_downloads SET size = ? WHERE id = ?',
      20,
      77
    )
    expect(db).to have_received(:close)
    expect(cmd).to have_received(:syscmd).with(
      "mount -t zfs #{pool_fs}/user.dataset@snap-2 \"#{mount_dir}\""
    )
    expect(cmd).to have_received(:pipe_cmd).with("tar -cz -C \"#{mount_dir}\" .")
    expect(cmd).to have_received(:syscmd).with(
      "umount \"#{mount_dir}\"",
      valid_rcs: [32]
    )

    allow(db).to receive(:prepared).with(
      'UPDATE snapshot_downloads SET size = ?, sha256sum = ? WHERE id = ?',
      3,
      'archive-sum',
      77
    )
    cmd.on_save(db)
    expect(db).to have_received(:prepared).with(
      'UPDATE snapshot_downloads SET size = ?, sha256sum = ? WHERE id = ?',
      3,
      'archive-sum',
      77
    )

    expect(cmd.rollback).to eq(ret: :ok)
    expect(File.exist?(cmd.send(:file_path))).to be(false)
    expect(Dir.exist?(cmd.send(:secret_dir_path))).to be(false)
  end

  it 'builds a full zfs send stream' do
    db = instance_spy(NodeCtld::Db, prepared: nil, close: nil)
    cmd = build_command(file_name: 'download.dat.gz', format: 'stream')

    allow(NodeCtld::Db).to receive(:new).and_return(db)
    allow(cmd).to receive(:zfs).and_return(double(output: (8 * 1024 * 1024).to_s))

    allow(cmd).to receive(:pipe_cmd).with(
      "zfs send #{pool_fs}/user.dataset@snap-2 | gzip"
    ) do
      FileUtils.mkdir_p(cmd.send(:secret_dir_path))
      File.binwrite(cmd.send(:file_path), 'stream')
      cmd.instance_variable_set(:@sum, 'stream-sum')
    end

    expect(cmd.exec).to eq(ret: :ok)
    expect(cmd).to have_received(:pipe_cmd).with(
      "zfs send #{pool_fs}/user.dataset@snap-2 | gzip"
    )
  end

  it 'builds an incremental zfs send stream' do
    db = instance_spy(NodeCtld::Db, prepared: nil, close: nil)
    stream = instance_double(NodeCtld::ZfsStream, size: 12)
    cmd = build_command(
      file_name: 'download.inc.dat.gz',
      format: 'incremental_stream',
      from_snapshot: 'snap-1'
    )

    allow(NodeCtld::Db).to receive(:new).and_return(db)
    allow(NodeCtld::ZfsStream).to receive(:new).and_return(stream)

    allow(cmd).to receive(:pipe_cmd).with(
      "zfs send -I @snap-1 #{pool_fs}/user.dataset@snap-2 | gzip"
    ) do
      FileUtils.mkdir_p(cmd.send(:secret_dir_path))
      File.binwrite(cmd.send(:file_path), 'incremental')
      cmd.instance_variable_set(:@sum, 'incremental-sum')
    end

    expect(cmd.exec).to eq(ret: :ok)
    expect(cmd).to have_received(:pipe_cmd).with(
      "zfs send -I @snap-1 #{pool_fs}/user.dataset@snap-2 | gzip"
    )
  end

  it 'returns ok when rollback runs after the file and directory already disappeared' do
    cmd = build_command(file_name: 'download.dat.gz', format: 'stream')

    expect(cmd.rollback).to eq(ret: :ok)
  end
end
