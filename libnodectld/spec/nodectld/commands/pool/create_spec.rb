# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/pool/create'

RSpec.describe NodeCtld::Commands::Pool::Create do
  let(:driver) { build_storage_driver }
  let(:daemon_class) do
    Class.new do
      def self.instance; end

      def refresh_pools; end
    end
  end
  let(:daemon) { instance_double(daemon_class, refresh_pools: nil) }
  let(:zfs_calls) { [] }

  def build_command(pool_fs:, pool_name: 'tank', options: { 'compression' => false })
    described_class.new(
      driver,
      'pool_id' => 123,
      'pool_name' => pool_name,
      'pool_fs' => pool_fs,
      'options' => options
    )
  end

  def stub_runtime(cmd, existing: false)
    allow(cmd).to receive(:zfs) do |action, opts, fs, **kwargs|
      zfs_calls << [action, opts, fs, kwargs]

      case action
      when :get
        double(exitstatus: existing ? 0 : 1, output: "#{fs}\n")
      when :create
        FileUtils.mkdir_p(File.join('/', fs))
        double(exitstatus: 0, output: '')
      else
        double(exitstatus: 0, output: '')
      end
    end
    allow(cmd).to receive(:osctl_pool).and_return(double(exitstatus: 0, output: ''))
    stub_const('NodeCtld::OsCtlUsers', Class.new)
    allow(NodeCtld::OsCtlUsers).to receive(:add_pool)
    stub_const('NodeCtld::Daemon', daemon_class)
    allow(NodeCtld::Daemon).to receive(:instance).and_return(daemon)
  end

  it 'creates runtime datasets, config paths, healthcheck file, and device grants' do
    Dir.mktmpdir('pool-create-spec') do |dir|
      pool_fs = File.join(dir.delete_prefix('/'), 'tank/spec')
      cmd = build_command(pool_fs: pool_fs)
      stub_runtime(cmd)

      expect(cmd.exec).to eq(ret: :ok)

      created = zfs_calls.select { |call| call[0] == :create }.map { |call| call[2] }
      expect(created).to include(
        pool_fs,
        "#{pool_fs}/vpsadmin",
        "#{pool_fs}/vpsadmin/config",
        "#{pool_fs}/vpsadmin/download",
        "#{pool_fs}/vpsadmin/mount"
      )
      expect(File.directory?(File.join('/', pool_fs, 'vpsadmin/config/vps'))).to be(true)
      expect(File.read(File.join('/', pool_fs, 'vpsadmin/download/_vpsadmin-download-healthcheck')))
        .to eq("123\n")
      expect(NodeCtld::OsCtlUsers).to have_received(:add_pool).with(pool_fs)
      expect(daemon).to have_received(:refresh_pools)

      cmd.send(:pool_devices).each do |ident, devnode|
        expect(cmd).to have_received(:osctl_pool).with(
          'tank',
          %i[group devices add],
          ['/default', *ident, 'rwm', devnode],
          { parents: true, inherit: false }
        )
      end

      cmd.rollback
      destroyed = zfs_calls.select { |call| call[0] == :destroy }.map { |call| call[2] }
      expect(destroyed).to include(
        "#{pool_fs}/vpsadmin/config",
        "#{pool_fs}/vpsadmin/download",
        "#{pool_fs}/vpsadmin/mount",
        "#{pool_fs}/vpsadmin",
        pool_fs
      )
      cmd.send(:pool_devices).map(&:first).each do |ident|
        expect(cmd).to have_received(:osctl_pool).with(
          'tank',
          %i[group devices del],
          ['/default', *ident],
          {},
          {},
          valid_rcs: [1]
        )
      end
    end
  end

  it 'updates options on existing datasets instead of failing' do
    Dir.mktmpdir('pool-create-existing-spec') do |dir|
      pool_fs = File.join(dir.delete_prefix('/'), 'tank/existing')
      FileUtils.mkdir_p(File.join('/', pool_fs, 'vpsadmin/download'))
      cmd = build_command(pool_fs: pool_fs)
      stub_runtime(cmd, existing: true)

      expect(cmd.exec).to eq(ret: :ok)
      expect(cmd).to have_received(:zfs).with(
        :set,
        'compression="off"',
        pool_fs
      )
      expect(zfs_calls.none? { |call| call[0] == :create }).to be(true)
    end
  end
end
