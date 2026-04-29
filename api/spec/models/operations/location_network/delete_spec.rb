# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::LocationNetwork::Delete do
  let(:loc_a) { SpecSeed.location }
  let(:loc_b) { SpecSeed.other_location }
  let(:network) { create_network! }

  def create_network!
    Network.create!(
      label: 'Spec Delete Location Network',
      address: '198.51.103.0',
      prefix: 24,
      ip_version: 4,
      role: :public_access,
      managed: true,
      split_access: :no_access,
      split_prefix: 32,
      purpose: :any,
      primary_location: loc_a
    )
  end

  it 'clears network primary location when deleting a primary link' do
    loc_net = LocationNetwork.create!(
      location: loc_a,
      network: network,
      primary: true
    )

    described_class.run(loc_net)

    expect(LocationNetwork.exists?(loc_net.id)).to be(false)
    expect(network.reload.primary_location).to be_nil
  end

  it 'leaves network primary location when deleting a non-primary link' do
    loc_net = LocationNetwork.create!(
      location: loc_b,
      network: network,
      primary: false
    )

    described_class.run(loc_net)

    expect(LocationNetwork.exists?(loc_net.id)).to be(false)
    expect(network.reload.primary_location).to eq(loc_a)
  end
end
