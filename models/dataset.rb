class Dataset < ActiveRecord::Base
  belongs_to :user
  has_many :dataset_in_pools
  has_many :snapshots

  has_ancestry cache_depth: true

  include Confirmable

  def full_name
    if parent_id
      "#{parent.full_name}/#{name}"
    else
      name
    end
  end
end
