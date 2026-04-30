# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::Export::EditHost do
  it 'passes the host and options to the edit chain' do
    host = instance_double(ExportHost)
    chain = instance_double(TransactionChain)
    opts = {
      rw: false,
      sync: true,
      subtree_check: false,
      root_squash: true
    }

    allow(TransactionChains::Export::EditHost).to receive(:fire)
      .with(host, opts)
      .and_return([chain, host])

    expect(described_class.run(host, opts)).to eq([chain, host])
  end
end
