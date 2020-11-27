class AddIpMailChecks < ActiveRecord::Migration
  def change
    add_column :user_requests, :ip_checked, :boolean, null: true
    add_column :user_requests, :ip_request_id, :string, limit: 50, null: true
    add_column :user_requests, :ip_success, :boolean, null: true
    add_column :user_requests, :ip_message, :string, limit: 255, null: true
    add_column :user_requests, :ip_errors, :text, null: true
    add_column :user_requests, :ip_proxy, :boolean, null: true
    add_column :user_requests, :ip_crawler, :boolean, null: true
    add_column :user_requests, :ip_recent_abuse, :boolean, null: true
    add_column :user_requests, :ip_vpn, :boolean, null: true
    add_column :user_requests, :ip_tor, :boolean, null: true
    add_column :user_requests, :ip_fraud_score, :integer, null: true

    add_column :user_requests, :mail_checked, :boolean, null: true
    add_column :user_requests, :mail_request_id, :string, limit: 50, null: true
    add_column :user_requests, :mail_success, :boolean, null: true
    add_column :user_requests, :mail_message, :string, limit: 255, null: true
    add_column :user_requests, :mail_errors, :text, null: true
    add_column :user_requests, :mail_valid, :boolean, null: true
    add_column :user_requests, :mail_disposable, :boolean, null: true
    add_column :user_requests, :mail_timed_out, :boolean, null: true
    add_column :user_requests, :mail_deliverability, :string, limit: 20, null: true
    add_column :user_requests, :mail_catch_all, :boolean, null: true
    add_column :user_requests, :mail_leaked, :boolean, null: true
    add_column :user_requests, :mail_suspect, :boolean, null: true
    add_column :user_requests, :mail_smtp_score, :integer, null: true
    add_column :user_requests, :mail_overall_score, :integer, null: true
    add_column :user_requests, :mail_fraud_score, :integer, null: true
    add_column :user_requests, :mail_dns_valid, :boolean, null: true
    add_column :user_requests, :mail_honeypot, :boolean, null: true
    add_column :user_requests, :mail_spam_trap_score, :string, limit: 20, null: true
    add_column :user_requests, :mail_recent_abuse, :boolean, null: true
    add_column :user_requests, :mail_frequent_complainer, :boolean, null: true
  end
end
