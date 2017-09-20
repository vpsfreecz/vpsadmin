class DatasetTree < ActiveRecord::Base
  belongs_to :dataset_in_pool
  has_many :branches

  include Confirmable
  include Lockable

  def full_name
    "tree.#{index}"
  end
end
