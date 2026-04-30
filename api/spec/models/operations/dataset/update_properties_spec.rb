# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::Dataset::UpdateProperties do
  let(:pool) { create_pool!(node: SpecSeed.node, role: :primary, refquota_check: true) }
  let!(:dataset_pair) do
    create_dataset_with_pool!(
      user: SpecSeed.user,
      pool: pool,
      name: "props-#{SecureRandom.hex(3)}",
      properties: { refquota: 10_240 }
    )
  end
  let(:dataset) { dataset_pair.first }
  let(:dip) { dataset_pair.last }
  let(:chain) { instance_double(TransactionChain) }

  before do
    allow(TransactionChains::Dataset::Set).to receive(:fire).and_return([chain, nil])
  end

  it 'checks refquota before calling the transaction chain' do
    expect do
      described_class.run(dataset, {}, {})
    end.to raise_error(VpsAdmin::API::Exceptions::PropertyInvalid, 'refquota must be set')

    expect(TransactionChains::Dataset::Set).not_to have_received(:fire)
  end

  it 'returns the chain returned by Dataset::Set.fire' do
    ret = described_class.run(dataset, { refquota: 12_288 }, { recursive: true })

    expect(ret).to eq(chain)
    expect(TransactionChains::Dataset::Set).to have_received(:fire).with(
      dip,
      { refquota: 12_288 },
      { recursive: true }
    )
  end
end
