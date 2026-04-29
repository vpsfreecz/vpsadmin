# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::TotpDevice::Create do
  let(:user) { SpecSeed.user }

  it 'retries on RecordNotUnique and eventually creates the device' do
    attempts = 0

    allow(UserTotpDevice).to receive(:create!).and_wrap_original do |method, *args, **kwargs|
      attempts += 1
      raise ActiveRecord::RecordNotUnique if attempts < 3

      method.call(*args, **kwargs)
    end

    device = described_class.run(user, 'Phone')

    expect(device).to be_persisted
    expect(device.user).to eq(user)
    expect(device.label).to eq('Phone')
    expect(attempts).to eq(3)
  end

  it 'raises OperationError after exhausting retries' do
    allow(UserTotpDevice).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique)

    expect do
      described_class.run(user, 'Phone')
    end.to raise_error(VpsAdmin::API::Exceptions::OperationError, 'unable to generate totp secret')

    expect(UserTotpDevice.where(user:, label: 'Phone')).to be_empty
  end
end
