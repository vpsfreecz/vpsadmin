# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/pool/authorize_rsync_key'

RSpec.describe NodeCtld::Commands::Pool::AuthorizeRsyncKey do
  let(:driver) { build_storage_driver }

  def build_command(pubkey)
    described_class.new(driver, 'pubkey' => pubkey)
  end

  it 'appends the key once and removes it on rollback' do
    Dir.mktmpdir('authorize-rsync-key') do |dir|
      cmd = build_command('ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA-test key@test')

      allow(cmd).to receive(:root_dir).and_return(dir)

      expect(cmd.exec).to eq(ret: :ok)
      expect(File.read(File.join(dir, '.ssh', 'authorized_keys'))).to eq(
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA-test key@test\n"
      )

      expect(cmd.exec).to eq(ret: :ok)
      expect(File.read(File.join(dir, '.ssh', 'authorized_keys')).lines).to eq(
        ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA-test key@test\n"]
      )

      expect(cmd.rollback).to eq(ret: :ok)
      expect(File.read(File.join(dir, '.ssh', 'authorized_keys'))).to eq('')
    end
  end
end
