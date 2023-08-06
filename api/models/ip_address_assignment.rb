class IpAddressAssignment < ActiveRecord::Base
  belongs_to :ip_address
  belongs_to :user
  belongs_to :vps
  belongs_to :assigned_by_chain, class_name: 'TransactionChain'
  belongs_to :unassigned_by_chain, class_name: 'TransactionChain'

  def raw_user_id
    user_id
  end

  def raw_vps_id
    vps_id
  end
end
