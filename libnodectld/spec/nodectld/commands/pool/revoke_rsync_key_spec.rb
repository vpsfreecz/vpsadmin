# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/pool/revoke_rsync_key'

RSpec.describe NodeCtld::Commands::Pool::RevokeRsyncKey do
  let(:driver) { build_storage_driver }

  def build_command(pubkey)
    described_class.new(driver, 'pubkey' => pubkey)
  end

  it 'removes matching keys and ignores missing files' do
    Dir.mktmpdir('revoke-rsync-key') do |dir|
      ssh_dir = File.join(dir, '.ssh')
      FileUtils.mkdir_p(ssh_dir)
      File.write(
        File.join(ssh_dir, 'authorized_keys'),
        [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA-keep keep@test\n",
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA-drop drop@test\n"
        ].join
      )

      cmd = build_command('ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA-drop drop@test')
      allow(cmd).to receive(:root_dir).and_return(dir)

      expect(cmd.exec).to eq(ret: :ok)
      expect(File.read(File.join(ssh_dir, 'authorized_keys'))).to eq(
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA-keep keep@test\n"
      )
      expect(cmd.rollback).to eq(ret: :ok)
    end
  end
end
