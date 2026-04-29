# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::TotpDevice::Confirm do
  let(:user) { SpecSeed.user }

  it 'rejects an already confirmed device' do
    device = create_totp_device!(user:, confirmed: true, enabled: true)

    expect do
      described_class.run(device, '000000')
    end.to raise_error(VpsAdmin::API::Exceptions::OperationError, 'the device is already confirmed')
  end

  it 'rejects an invalid code' do
    device = create_totp_device!(user:, confirmed: false, enabled: false)

    expect do
      described_class.run(device, '000000')
    end.to raise_error(VpsAdmin::API::Exceptions::OperationError, 'invalid totp code')

    expect(device.reload.confirmed).to be(false)
    expect(device.enabled).to be(false)
  end

  it 'confirms and enables the device, stores recovery code, and enables user MFA' do
    device = create_totp_device!(user:, confirmed: false, enabled: false)
    user.update!(enable_multi_factor_auth: false)
    t = Time.at(1_700_000_000)
    allow(Time).to receive(:now).and_return(t)

    recovery_code = described_class.run(device, device.totp.at(t))

    expect(recovery_code).to match(/\A[0-9a-f]{40}\z/)
    expect(device.reload.confirmed).to be(true)
    expect(device.enabled).to be(true)
    expect(
      VpsAdmin::API::CryptoProviders::Bcrypt.matches?(device.recovery_code, nil, recovery_code)
    ).to be(true)
    expect(user.reload.enable_multi_factor_auth).to be(true)
  end
end
