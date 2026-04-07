# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/vps/deploy_public_key'
require 'tmpdir'

RSpec.describe NodeCtld::Commands::Vps::DeployPublicKey do
  let(:driver) { build_storage_driver }
  let(:pubkey) { 'ssh-ed25519 ZGVwbG95LXB1YmtleQ== deploy@test' }
  let(:tmp_dir) { Dir.mktmpdir('deploy-public-key-spec') }
  let(:root_dir) { File.join(tmp_dir, 'root') }
  let(:cmd) do
    described_class.new(
      driver,
      'vps_id' => 101,
      'pubkey' => pubkey
    )
  end

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  before do
    allow(cmd).to receive(:root_dir).and_return(root_dir)
    allow(cmd).to receive(:fork_chroot_wait) do |&block|
      block.call
      0
    end
  end

  it 'creates authorized_keys and stores the key once' do
    expect(cmd.exec).to eq(ret: :ok)

    authorized_keys = File.join(root_dir, '.ssh', 'authorized_keys')

    expect(File.read(authorized_keys)).to eq("#{pubkey}\n")
    expect(File.stat(File.join(root_dir, '.ssh')).mode & 0o777).to eq(0o700)
    expect(File.stat(authorized_keys).mode & 0o777).to eq(0o600)
  end

  it 'does not duplicate an existing key and removes it on rollback' do
    ssh_dir = File.join(root_dir, '.ssh')
    authorized_keys = File.join(ssh_dir, 'authorized_keys')

    FileUtils.mkdir_p(ssh_dir, mode: 0o700)
    File.write(authorized_keys, "#{pubkey}\n")

    expect(cmd.exec).to eq(ret: :ok)
    expect(File.read(authorized_keys)).to eq("#{pubkey}\n")

    expect(cmd.rollback).to eq(ret: :ok)
    expect(File.read(authorized_keys)).to eq('')
  end
end
