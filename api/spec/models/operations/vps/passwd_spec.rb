# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::Vps::Passwd do
  let(:vps) { instance_double(Vps) }
  let(:chain) { instance_double(TransactionChain) }

  it 'generates secure passwords and returns the passwd chain' do
    allow(TransactionChains::Vps::Passwd).to receive(:fire) do |arg_vps, password|
      expect(arg_vps).to eq(vps)
      expect(password).to match(/\A[a-zA-Z0-9]{20}\z/)
      [chain, nil]
    end

    ret_chain, password = described_class.run(vps, 'secure')

    expect(ret_chain).to eq(chain)
    expect(password.length).to eq(20)
  end

  it 'generates simple passwords from the restricted character set' do
    allow(TransactionChains::Vps::Passwd).to receive(:fire) do |_arg_vps, password|
      expect(password).to match(/\A[a-z2-9]{8}\z/)
      [chain, nil]
    end

    ret_chain, password = described_class.run(vps, 'simple')

    expect(ret_chain).to eq(chain)
    expect(password.length).to eq(8)
  end

  it 'raises for unknown password types' do
    expect do
      described_class.run(vps, 'rot13')
    end.to raise_error(RuntimeError, 'unknown password type "rot13"')
  end
end
