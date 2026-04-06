# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Vps::Clone do
  around do |example|
    with_current_context { example.run }
  end

  let(:user) { SpecSeed.user }

  def create_vps_fixture
    src_node = SpecSeed.node
    src_pool = create_pool!(node: src_node, role: :hypervisor)
    _dataset, dip = create_dataset_with_pool!(
      user: user,
      pool: src_pool,
      name: "clone-root-#{SecureRandom.hex(4)}"
    )
    vps = create_vps_for_dataset!(user: user, node: src_node, dataset_in_pool: dip)
    dst_node = create_node!(
      location: src_node.location,
      role: :node,
      name: "clone-dst-#{SecureRandom.hex(3)}"
    )

    [vps, dst_node]
  end

  it 'returns OsToOs for vpsadminos to vpsadminos clones' do
    vps, dst_node = create_vps_fixture

    expect(described_class.chain_for(vps, dst_node)).to eq(TransactionChains::Vps::Clone::OsToOs)
  end

  it 'rejects unsupported hypervisor combinations' do
    vps, = create_vps_fixture
    openvz_node = create_node!(
      location: SpecSeed.location,
      role: :node,
      hypervisor_type: :openvz,
      name: "openvz-#{SecureRandom.hex(3)}"
    )

    expect do
      described_class.chain_for(vps, openvz_node)
    end.to raise_error(
      VpsAdmin::API::Exceptions::OperationNotSupported,
      /Clone from vpsadminos to openvz is not supported/
    )
  end
end
