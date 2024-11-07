class DnsRecordLog < ApplicationRecord
  belongs_to :dns_zone
  belongs_to :user
  belongs_to :transaction_chain

  enum :change_type, %i[create_record update_record delete_record]
  serialize :attr_changes, coder: JSON

  validates :dns_zone_name, :name, :record_type, :attr_changes, presence: true

  def raw_user_id
    user_id
  end
end
