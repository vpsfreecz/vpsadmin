class Dataset < ActiveRecord::Base
  belongs_to :parent_dataset, class_name: 'Dataset', foreign_key: :parent_id
  belongs_to :user
  has_many :dataset_in_pools
  has_many :snapshots

  def full_name
    if parent_id
      "#{parent_dataset.full_name}/#{name}"
    else
      name
    end
  end
end
