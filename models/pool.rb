class Pool < ActiveRecord::Base
  belongs_to :node
  has_many :dataset_in_pools
  has_many :dataset_properties
  has_many :dataset_actions
  has_many :snapshot_downloads

  enum role: %i(hypervisor primary backup)

  validates :node_id, :label, :filesystem, :role, presence: true

  include Lockable
  include VpsAdmin::API::DatasetProperties::Model

  include VpsAdmin::API::Maintainable::Model
  include VpsAdmin::API::Maintainable::Check

  maintenance_parents :node

  def self.create!(attrs, properties)
    pool = new(attrs)
    TransactionChains::Pool::Create.fire(pool, properties)
  end
end
