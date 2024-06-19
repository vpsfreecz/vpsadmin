require_relative 'confirmable'
require_relative 'lockable'

class Branch < ApplicationRecord
  belongs_to :dataset_tree
  has_many :snapshot_in_pool_in_branches

  include Confirmable
  include Lockable

  def full_name
    "branch-#{name}.#{index}"
  end
end
