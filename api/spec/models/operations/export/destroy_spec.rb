# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::Export::Destroy do
  it 'destroys the export and returns only the chain' do
    export = instance_double(Export)
    chain = instance_double(TransactionChain)

    allow(TransactionChains::Export::Destroy).to receive(:fire)
      .with(export)
      .and_return([chain, export])

    expect(described_class.run(export)).to eq(chain)
  end
end
