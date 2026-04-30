# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::Export::DelHost do
  it 'deletes one host and returns only the chain' do
    export = instance_double(Export)
    host = instance_double(ExportHost)
    chain = instance_double(TransactionChain)

    allow(TransactionChains::Export::DelHosts).to receive(:fire)
      .with(export, [host])
      .and_return([chain, [host]])

    expect(described_class.run(export, host)).to eq(chain)
  end
end
