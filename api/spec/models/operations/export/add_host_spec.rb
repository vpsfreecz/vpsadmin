# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::Export::AddHost do
  around do |example|
    with_current_context(user: SpecSeed.user) { example.run }
  end

  let(:fixture) { create_netif_vps_fixture! }
  let(:export) do
    create_export_for_dataset!(
      dataset_in_pool: fixture.fetch(:dataset_in_pool)
    ).first.tap do |row|
      row.update!(
        rw: true,
        sync: false,
        subtree_check: true,
        root_squash: false
      )
    end
  end
  let(:ip) do
    create_ipv4_address_in_network!(
      network: create_private_network!(split_prefix: 24),
      location: SpecSeed.location,
      user: SpecSeed.user
    )
  end
  let(:chain) { instance_double(TransactionChain) }

  it 'inherits nil host flags from the export defaults' do
    returned_host = nil

    allow(TransactionChains::Export::AddHosts).to receive(:fire) do |_arg_export, hosts|
      returned_host = hosts.first
      [chain, hosts]
    end

    ret_chain, ret_host = described_class.run(
      export,
      ip_address: ip,
      rw: nil,
      sync: nil,
      subtree_check: nil,
      root_squash: nil
    )

    expect(ret_chain).to eq(chain)
    expect(ret_host).to eq(returned_host)
    expect(returned_host.export).to eq(export)
    expect(returned_host.ip_address).to eq(ip)
    expect(returned_host.rw).to eq(export.rw)
    expect(returned_host.sync).to eq(export.sync)
    expect(returned_host.subtree_check).to eq(export.subtree_check)
    expect(returned_host.root_squash).to eq(export.root_squash)
  end

  it 'keeps explicit false values instead of falling back to defaults' do
    allow(TransactionChains::Export::AddHosts).to receive(:fire) do |_arg_export, hosts|
      [chain, hosts]
    end

    _ret_chain, host = described_class.run(
      export,
      ip_address: ip,
      rw: false,
      sync: true,
      subtree_check: false,
      root_squash: true
    )

    expect(host.rw).to be(false)
    expect(host.sync).to be(true)
    expect(host.subtree_check).to be(false)
    expect(host.root_squash).to be(true)
    expect(TransactionChains::Export::AddHosts).to have_received(:fire)
      .with(export, [host])
  end
end
