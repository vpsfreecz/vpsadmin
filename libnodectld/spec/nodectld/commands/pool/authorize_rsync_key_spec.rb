# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/pool/authorize_rsync_key'

RSpec.describe NodeCtld::Commands::Pool::AuthorizeRsyncKey do
  let(:chain_id) { 123 }
  let(:driver) { build_storage_driver(chain_id: chain_id) }
  let(:pubkey) { 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA-test key@test' }
  let(:authorized_key) { "#{pubkey} vpsadmin-rsync-chain=#{chain_id}" }

  def build_command(pubkey)
    described_class.new(driver, 'pubkey' => pubkey)
  end

  it 'writes the chain-marked key once and removes it on rollback' do
    Dir.mktmpdir('authorize-rsync-key') do |dir|
      cmd = build_command(pubkey)

      allow(cmd).to receive(:root_dir).and_return(dir)

      expect(cmd.exec).to eq(ret: :ok)
      expect(File.read(File.join(dir, '.ssh', 'authorized_keys'))).to eq(
        "#{authorized_key}\n"
      )

      expect(cmd.exec).to eq(ret: :ok)
      expect(File.read(File.join(dir, '.ssh', 'authorized_keys')).lines).to eq(
        ["#{authorized_key}\n"]
      )

      expect(cmd.rollback).to eq(ret: :ok)
      expect(File.read(File.join(dir, '.ssh', 'authorized_keys'))).to eq('')
    end
  end

  it 'keeps matching keys that were not authorized by this chain' do
    Dir.mktmpdir('authorize-rsync-key') do |dir|
      ssh_dir = File.join(dir, '.ssh')
      authorized_keys = File.join(ssh_dir, 'authorized_keys')
      cmd = build_command(pubkey)

      FileUtils.mkdir_p(ssh_dir)
      File.write(authorized_keys, "#{pubkey}\n")
      allow(cmd).to receive(:root_dir).and_return(dir)

      expect(cmd.exec).to eq(ret: :ok)
      expect(File.read(authorized_keys).lines).to eq(
        [
          "#{pubkey}\n",
          "#{authorized_key}\n"
        ]
      )

      expect(cmd.rollback).to eq(ret: :ok)
      expect(File.read(authorized_keys)).to eq("#{pubkey}\n")
    end
  end
end
