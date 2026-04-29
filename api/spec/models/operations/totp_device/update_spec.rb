# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::TotpDevice::Update do
  it 'changes the label only' do
    device = create_totp_device!(user: SpecSeed.user, label: 'Old', confirmed: true, enabled: true)

    result = described_class.run(device, label: 'New')

    expect(result).to eq(device)
    expect(device.reload.label).to eq('New')
    expect(device.confirmed).to be(true)
    expect(device.enabled).to be(true)
  end
end
