# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::Export::Create do
  it 'passes the dataset and options to the create chain' do
    dataset = instance_double(Dataset)
    export = instance_double(Export)
    chain = instance_double(TransactionChain)
    opts = {
      all_vps: true,
      rw: true,
      sync: false,
      subtree_check: false,
      root_squash: true,
      threads: 4,
      enabled: true
    }

    allow(TransactionChains::Export::Create).to receive(:fire)
      .with(dataset, opts)
      .and_return([chain, export])

    expect(described_class.run(dataset, opts)).to eq([chain, export])
  end
end
