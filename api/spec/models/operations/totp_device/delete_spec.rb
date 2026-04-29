# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::TotpDevice::Delete do
  it 'removes the device' do
    device = create_totp_device!(user: SpecSeed.user)

    described_class.run(device)

    expect(UserTotpDevice.exists?(device.id)).to be(false)
  end
end
