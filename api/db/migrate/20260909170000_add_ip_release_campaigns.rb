class AddIpReleaseCampaigns < ActiveRecord::Migration[8.1]
  def change
    create_table :ip_release_campaigns do |t|
      t.string :label, null: false, limit: 200
      t.datetime :deadline, null: false
      t.boolean :allow_keep, null: false, default: true
      t.bigint :created_by_id, null: false
      t.bigint :updated_by_id, null: false
      t.datetime :closed_at
      t.bigint :closed_by_id
      t.timestamps
    end

    create_table :ip_release_requests do |t|
      t.bigint :ip_release_campaign_id, null: false
      t.bigint :user_id, null: false
      t.timestamps
      t.index %i[ip_release_campaign_id user_id], unique: true, name: :ip_release_request_user
      t.index :user_id
    end

    create_table :ip_release_request_notices do |t|
      t.bigint :ip_release_request_id, null: false
      t.bigint :mail_log_id, null: false
      t.string :event, null: false, limit: 16
      t.bigint :created_by_id, null: false
      t.timestamps
      t.index :ip_release_request_id, name: :ip_release_notice_request
    end

    create_table :ip_release_request_addresses do |t|
      t.bigint :ip_release_request_id, null: false
      t.bigint :ip_address_id, null: false
      t.bigint :active_ip_address_id
      t.bigint :network_id, null: false
      t.string :address, null: false, limit: 43
      t.integer :prefix, null: false
      t.decimal :size, precision: 40, scale: 0, null: false
      t.text :keep_reason
      t.datetime :kept_at
      t.bigint :kept_by_id
      t.text :exemption_reason
      t.datetime :exempted_at
      t.bigint :exempted_by_id
      t.datetime :excluded_at
      t.string :exclusion_reason
      t.datetime :released_at
      t.bigint :released_by_id
      t.bigint :release_chain_id
      t.datetime :last_attempt_at
      t.string :last_result
      t.text :last_error
      t.timestamps
      t.index :ip_release_request_id, name: :ip_release_address_request
      t.index :active_ip_address_id, unique: true, name: :ip_release_active_address
      t.index :ip_address_id
    end
  end
end
