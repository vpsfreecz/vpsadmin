# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe VpsAdmin::DownloadMounter::Mounter do
  def build_pool(id: 123)
    environment = Struct.new(:domain).new('example.test')
    location = Struct.new(:environment).new(environment)
    node = Struct.new(:domain_name, :ip_addr, :location).new(
      'node1.lab',
      '192.0.2.10',
      location
    )

    Struct.new(:id, :filesystem, :node).new(id, 'tank/ct', node)
  end

  describe '#mount' do
    let(:pool) { build_pool }
    let(:mounter) { described_class.new({}, '/mnt/download', pool) }
    let(:mountpoint) { '/mnt/download/node1.lab.example.test/123' }
    let(:src) { '192.0.2.10:/tank/ct/vpsadmin/download' }

    it 'remounts a mounted directory when the healthcheck fails' do
      commands = []

      allow(mounter).to receive_messages(
        create_mountpoint: true,
        mounted?: true,
        mountpoint_exists?: true
      )
      allow(mounter).to receive(:mounted_healthy?).and_return(false, true)
      allow(mounter).to receive(:run) do |*cmd, **_kwargs|
        commands << cmd
        true
      end

      expect(mounter.mount).to be(true)
      expect(commands).to eq([
                               ['umount', '-f', mountpoint],
                               ['mount', '-t', 'nfs', '-overs=3,nolock', src, mountpoint]
                             ])
    end

    it 'keeps treating mountpoint EEXIST as a stale mount' do
      commands = []

      allow(mounter).to receive_messages(
        mounted_healthy?: true,
        mountpoint_exists?: false
      )
      allow(mounter).to receive(:create_mountpoint).and_return(false, true)
      allow(mounter).to receive(:run) do |*cmd, **_kwargs|
        commands << cmd
        true
      end

      expect(mounter.mount).to be(true)
      expect(commands).to eq([
                               ['umount', '-f', mountpoint],
                               ['mount', '-t', 'nfs', '-overs=3,nolock', src, mountpoint]
                             ])
    end
  end

  describe '#mounted_healthy?' do
    let(:pool) { build_pool(id: 456) }

    it 'accepts a mounted pool with the expected healthcheck content' do
      Dir.mktmpdir do |dir|
        mounter = described_class.new({}, dir, pool)

        FileUtils.mkdir_p(File.dirname(mounter.send(:healthcheck_path)))
        File.write(mounter.send(:healthcheck_path), "456\n")

        expect(mounter.send(:mounted_healthy?)).to be(true)
      end
    end

    it 'rejects a mounted pool with unexpected healthcheck content' do
      Dir.mktmpdir do |dir|
        mounter = described_class.new({}, dir, pool)

        FileUtils.mkdir_p(File.dirname(mounter.send(:healthcheck_path)))
        File.write(mounter.send(:healthcheck_path), "999\n")

        expect(mounter.send(:mounted_healthy?)).to be(false)
      end
    end
  end
end
