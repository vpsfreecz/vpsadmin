# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::LocationNetwork::Update do
  let(:loc_a) { SpecSeed.location }
  let(:loc_b) { SpecSeed.other_location }
  let(:network) { create_network! }

  def create_network!
    Network.create!(
      label: 'Spec Update Location Network',
      address: '198.51.102.0',
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

  it 'clears network primary location when a primary link is made non-primary' do
    loc_net = LocationNetwork.create!(
      location: loc_a,
      network: network,
      primary: true
    )

    described_class.run(loc_net, { primary: false })

    expect(loc_net.reload.primary).to be_nil
    expect(network.reload.primary_location).to be_nil
  end

  it 'sets network primary location when a non-primary link is made primary' do
    loc_net = LocationNetwork.create!(
      location: loc_b,
      network: network,
      primary: false
    )

    described_class.run(loc_net, { primary: true })

    expect(loc_net.reload.primary).to be(true)
    expect(network.reload.primary_location).to eq(loc_b)
  end

  it 'switches the primary link cleanly when another link is promoted' do
    current = LocationNetwork.create!(
      location: loc_a,
      network: network,
      primary: true
    )
    promoted = LocationNetwork.create!(
      location: loc_b,
      network: network,
      primary: false
    )

    described_class.run(promoted, { primary: true })

    expect(current.reload.primary).to be_nil
    expect(promoted.reload.primary).to be(true)
    expect(network.reload.primary_location).to eq(loc_b)
  end
end
