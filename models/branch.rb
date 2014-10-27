class Branch < ActiveRecord::Base
  belongs_to :dataset_tree
  has_many :snapshot_in_pool_in_branches

  include Confirmable

  def full_name
    "branch-#{name}.#{index}"
  end
end
