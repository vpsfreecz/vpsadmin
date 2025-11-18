require_relative 'confirmable'
require_relative 'lockable'

class StorageVolume < ApplicationRecord
  belongs_to :storage_pool
  belongs_to :user
  belongs_to :vps
  has_many :vpses
  has_many :rescue_vpses, foreign_key: :rescue_volume_id
  has_many :vps_io_stats

  enum :format, %i[raw qcow2]

  include Confirmable
  include Lockable

  include VpsAdmin::API::ClusterResources

  cluster_resources required: %i[diskspace],
                    environment: -> { storage_pool.node.location.environment }

  # TODO: validations
end
