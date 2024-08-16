class DnsRecordLog < ApplicationRecord
  belongs_to :dns_zone
  belongs_to :user
  enum change_type: %i[create_record update_record delete_record]
  serialize :attr_changes, coder: JSON
end
