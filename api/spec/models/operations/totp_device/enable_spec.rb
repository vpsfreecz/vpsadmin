# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::TotpDevice::Enable do
  let(:user) { SpecSeed.user }

  it 'rejects an unconfirmed device' do
    device = create_totp_device!(user:, confirmed: false, enabled: false)

    expect do
      described_class.run(device)
    end.to raise_error(VpsAdmin::API::Exceptions::OperationError, 'unconfirmed device cannot be enabled')
  end

  it 'enables the device and toggles user MFA on when needed' do
    device = create_totp_device!(user:, confirmed: true, enabled: false)
    user.update!(enable_multi_factor_auth: false)

    result = described_class.run(device)

    expect(result).to eq(device)
    expect(device.reload.enabled).to be(true)
    expect(user.reload.enable_multi_factor_auth).to be(true)
  end
end
