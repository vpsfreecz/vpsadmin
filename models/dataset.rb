class Dataset < ActiveRecord::Base
  belongs_to :dataset, foreign_key: :parent_id
  has_many :dataset_in_pools

  def full_name
    name # FIXME
  end
end
