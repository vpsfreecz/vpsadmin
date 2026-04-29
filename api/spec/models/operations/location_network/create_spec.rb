# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::LocationNetwork::Create do
  let(:loc_a) { SpecSeed.location }
  let(:loc_b) { SpecSeed.other_location }
  let(:network) { create_network! }

  def create_network!
    Network.create!(
      label: 'Spec Create Location Network',
      address: '198.51.101.0',
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

  it 'creates a location network' do
    expect do
      described_class.run({ location: loc_b, network: network, primary: false })
    end.to change(LocationNetwork, :count).by(1)
  end

  it 'updates network primary location when creating a primary link' do
    loc_net = described_class.run({ location: loc_b, network: network, primary: true })

    expect(loc_net.reload.primary).to be(true)
    expect(network.reload.primary_location).to eq(loc_b)
  end

  it 'leaves network primary location alone when creating a non-primary link' do
    loc_net = described_class.run({ location: loc_b, network: network, primary: false })

    expect(loc_net.reload.primary).to be_nil
    expect(network.reload.primary_location).to eq(loc_a)
  end
end
