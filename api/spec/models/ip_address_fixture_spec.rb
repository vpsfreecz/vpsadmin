require 'spec_helper'

RSpec.describe StorageChainSpecHelpers do
  it 'avoids existing addresses when auto-increment IDs repeat the default address offset' do
    with_current_context do
      occupied = %w[192.0.2.20 192.0.2.21]
      occupied.each { |addr| create_ip_address!(addr:) }
      # Rolled-back examples advance the database sequence without retaining rows.
      allow(IpAddress).to receive(:maximum).with(:id).and_return(200)
      address = create_ip_address!
      expect(occupied).not_to include(address.addr)
      expect(address.network).to eq(SpecSeed.network_v4)
      expect { create_ip_address!(addr: occupied.first) }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end
end
