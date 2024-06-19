require_relative 'confirmable'
require_relative 'lockable'

class DatasetTree < ApplicationRecord
  belongs_to :dataset_in_pool
  has_many :branches

  include Confirmable
  include Lockable

  def full_name
    "tree.#{index}"
  end
end
