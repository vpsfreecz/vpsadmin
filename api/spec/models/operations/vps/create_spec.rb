# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::Vps::Create do
  around do |example|
    with_current_context(user: SpecSeed.user) { example.run }
  end

  def build_attrs(template)
    {
      user: SpecSeed.user,
      node: SpecSeed.node,
      hostname: "op-create-#{SecureRandom.hex(4)}",
      os_template: template,
      dns_resolver: SpecSeed.dns_resolver,
      user_namespace_map: create_user_namespace_map!(user: SpecSeed.user),
      object_state: :active,
      confirmed: :confirmed
    }
  end

  it 'builds and validates a VPS, normalizes user data, and delegates to the create chain' do
    template = create_os_template!(manage_hostname: false)
    attrs = build_attrs(template)
    resources = {
      cpu: 2,
      memory: 2048,
      diskspace: 10_240,
      swap: 512
    }
    opts = {
      start: false,
      user_data_format: 'script',
      user_data_content: "#!/bin/sh\necho create\n"
    }
    chain = instance_double(TransactionChain)
    created_vps = nil

    allow(TransactionChains::Vps::Create).to receive(:fire) do |vps, chain_opts|
      created_vps = vps
      expect(chain_opts[:vps_user_data]).to be_a(VpsUserData)
      expect(chain_opts).not_to include(:user_data_format, :user_data_content)
      [chain, vps]
    end

    expect(described_class.run(attrs, resources, opts)).to eq([chain, created_vps])
    expect(created_vps).to be_new_record
    expect(created_vps.manage_hostname).to be(false)
    expect(created_vps.cpu).to eq(2)
    expect(created_vps.memory).to eq(2048)
    expect(created_vps.diskspace).to eq(10_240)
    expect(created_vps.swap).to eq(512)
  end

  it 'raises RecordInvalid before calling the chain when the VPS is invalid' do
    template = create_os_template!
    attrs = build_attrs(template).merge(hostname: '-invalid-')

    allow(TransactionChains::Vps::Create).to receive(:fire)

    expect do
      described_class.run(attrs, { cpu: 1, memory: 1024, diskspace: 10_240 }, {})
    end.to raise_error(ActiveRecord::RecordInvalid)

    expect(TransactionChains::Vps::Create).not_to have_received(:fire)
  end
end
