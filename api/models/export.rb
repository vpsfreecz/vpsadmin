require 'vpsadmin/api/lifetimes'
require_relative 'confirmable'
require_relative 'lockable'
require_relative 'transaction_chains/export/destroy'

class Export < ::ActiveRecord::Base
  belongs_to :dataset_in_pool
  belongs_to :snapshot_in_pool_clone
  belongs_to :user
  has_many :export_hosts
  has_one :network_interface
  has_many :ip_addresses, through: :network_interface
  has_many :host_ip_addresses, through: :network_interface

  include Confirmable
  include Lockable

  include VpsAdmin::API::Lifetimes::Model
  set_object_states states: %i(active deleted),
                    deleted: {
                      enter: TransactionChains::Export::Destroy,
                    }

  def dataset
    dataset_in_pool.dataset
  end

  def snapshot
    snapshot_in_pool_clone && snapshot_in_pool_clone.snapshot_in_pool.snapshot
  end

  def ip_address
    ip_addresses.first
  end

  def host_ip_address
    host_ip_addresses.first
  end
end
