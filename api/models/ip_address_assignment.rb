class IpAddressAssignment < ActiveRecord::Base
  belongs_to :ip_address
  belongs_to :user
  belongs_to :vps
  belongs_to :assigned_by_chain, class_name: 'TransactionChain'
  belongs_to :unassigned_by_chain, class_name: 'TransactionChain'
end
