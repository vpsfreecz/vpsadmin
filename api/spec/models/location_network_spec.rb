# frozen_string_literal: true

require 'spec_helper'

RSpec.describe LocationNetwork do
  let(:location) { SpecSeed.location }
  let(:network) do
    Network.create!(
      label: 'Spec Location Network',
      address: '198.51.100.0',
      prefix: 24,
      ip_version: 4,
      role: :public_access,
      managed: true,
      split_access: :no_access,
      split_prefix: 32,
      purpose: :any,
      primary_location: location
    )
  end

  it 'normalizes primary false to nil before save' do
    loc_net = described_class.create!(
      location: location,
      network: network,
      primary: false
    )

    expect(loc_net.reload.primary).to be_nil
  end

  it 'keeps primary true before save' do
    loc_net = described_class.create!(
      location: location,
      network: network,
      primary: true
    )

    expect(loc_net.reload.primary).to be(true)
  end

  it 'requires a location' do
    loc_net = described_class.new(network: network)

    expect(loc_net).not_to be_valid
    expect(loc_net.errors[:location]).to include("can't be blank")
  end

  it 'requires a network' do
    loc_net = described_class.new(location: location)

    expect(loc_net).not_to be_valid
    expect(loc_net.errors[:network]).to include("can't be blank")
  end
end
