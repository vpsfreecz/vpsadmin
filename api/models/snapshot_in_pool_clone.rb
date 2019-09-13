require_relative 'confirmable'
require_relative 'lockable'

class SnapshotInPoolClone < ActiveRecord::Base
  belongs_to :snapshot_in_pool
  belongs_to :user_namespace_map
  has_many :mounts
  enum state: %i(active inactive)

  include Confirmable
  include Lockable
end
