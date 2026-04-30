# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::Vps::SetFeatures do
  around do |example|
    with_current_context(user: SpecSeed.user) { example.run }
  end

  let(:fixture) { build_standalone_vps_fixture }
  let(:vps) do
    fixture.fetch(:vps).tap do |row|
      seed_vps_features!(row)
      row.vps_features.reload
    end
  end
  let(:chain) { instance_double(TransactionChain) }

  it 'toggles only supplied features and returns the features chain' do
    captured_features = nil
    original_tun = vps.vps_features.find_by!(name: 'tun').enabled

    allow(TransactionChains::Vps::Features).to receive(:fire) do |arg_vps, features|
      captured_features = features
      [chain, arg_vps]
    end

    expect(described_class.run(vps, ppp: true)).to eq(chain)
    expect(captured_features.find { |f| f.name == 'ppp' }.enabled).to be(true)
    expect(captured_features.find { |f| f.name == 'tun' }.enabled).to eq(original_tun)
    expect(TransactionChains::Vps::Features).to have_received(:fire).with(vps, captured_features)
  end

  it 'raises when the resulting feature set contains a conflict' do
    tun_feature = VpsFeature::FEATURES.fetch(:tun)

    allow(tun_feature).to receive(:conflict?).and_call_original
    allow(tun_feature).to receive(:conflict?).with(:fuse).and_return(true)

    expect do
      described_class.run(vps, {})
    end.to raise_error(VpsAdmin::API::Exceptions::VpsFeatureConflict, /tun.*fuse/)
  end
end
