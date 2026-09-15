require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20260909170000_add_ip_release_campaigns')

RSpec.describe AddIpReleaseCampaigns do
  it 'creates the campaign tables and allows only one active claim per IP' do
    migrate_up!
    expect(table_exists?(:ip_release_request_notices)).to be(true)
    expect(column(:ip_release_campaigns, :allow_keep).default).to be(true)
    attrs = {
      ip_release_request_id: 1, ip_address_id: 10, active_ip_address_id: 10,
      network_id: 1, address: '192.0.2.10', prefix: 32, size: 1,
      created_at: timestamp, updated_at: timestamp
    }
    insert_row(:ip_release_request_addresses, attrs)
    expect { insert_row(:ip_release_request_addresses, attrs) }
      .to raise_error(ActiveRecord::RecordNotUnique)
    2.times { insert_row(:ip_release_request_addresses, attrs.merge(active_ip_address_id: nil)) }
  end

  it 'removes only the new tables on rollback' do
    migrate_up!
    migrate_down!
    expect(table_exists?(:ip_release_campaigns)).to be(false)
    expect(table_exists?(:ip_release_requests)).to be(false)
    expect(table_exists?(:ip_release_request_notices)).to be(false)
    expect(table_exists?(:ip_release_request_addresses)).to be(false)
  end
end
