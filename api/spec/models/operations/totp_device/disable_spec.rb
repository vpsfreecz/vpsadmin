# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::TotpDevice::Disable do
  it 'disables the device' do
    device = create_totp_device!(user: SpecSeed.user, confirmed: true, enabled: true)

    result = described_class.run(device)

    expect(result).to eq(device)
    expect(device.reload.enabled).to be(false)
  end
end
