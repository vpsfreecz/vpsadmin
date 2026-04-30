# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::Export::Update do
  it 'passes the export and options to the update chain' do
    export = instance_double(Export)
    chain = instance_double(TransactionChain)
    opts = {
      all_vps: false,
      rw: false,
      sync: true,
      subtree_check: true,
      root_squash: false,
      threads: 12,
      enabled: false
    }

    allow(TransactionChains::Export::Update).to receive(:fire)
      .with(export, opts)
      .and_return([chain, export])

    expect(described_class.run(export, opts)).to eq([chain, export])
  end
end
