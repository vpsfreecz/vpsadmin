class Dataset < ActiveRecord::Base
  belongs_to :user
  has_many :dataset_in_pools
  has_many :snapshots

  has_ancestry cache_depth: true

  validates :name, format: {
      with: /\A[a-zA-Z0-9][a-zA-Z0-9_\-:\.]{0,499}\z/,
      message: "'%{value}' is not a valid dataset name"
  }

  include Confirmable

  def full_name
    if parent_id
      "#{parent.full_name}/#{name}"
    else
      name
    end
  end
end
