# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/pool/authorize_send_key'

RSpec.describe NodeCtld::Commands::Pool::AuthorizeSendKey do
  let(:driver) { build_storage_driver }
  let(:pubkey) { 'ssh-ed25519 AAAATEST pool@test' }
  let(:cmd) do
    described_class.new(
      driver,
      'pool_name' => 'tank',
      'name' => 'migration-101',
      'ctid' => 101,
      'passphrase' => 'secret',
      'pubkey' => pubkey
    )
  end

  it 'authorizes a single-use send key and removes it on rollback' do
    allow(cmd).to receive(:osctl_pool).and_return(ret: :ok)

    expect(cmd.exec).to eq(ret: :ok)
    expect(cmd).to have_received(:osctl_pool).with(
      'tank',
      %i[receive authorized-keys add],
      'migration-101',
      { ctid: 101, passphrase: 'secret', single_use: true },
      {},
      { input: pubkey }
    )

    expect(cmd.rollback).to eq(ret: :ok)
    expect(cmd).to have_received(:osctl_pool).with(
      'tank',
      %i[receive authorized-keys del],
      'migration-101',
      {},
      {},
      { valid_rcs: [1] }
    )
  end
end
