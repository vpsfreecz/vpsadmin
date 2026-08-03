require_relative 'confirmable'
require_relative 'lockable'

class DatasetTree < ApplicationRecord
  belongs_to :dataset_in_pool
  has_many :branches
  operation_event_owner via: %i[dataset_in_pool dataset user]

  include Confirmable
  include Lockable

  def full_name
    "tree.#{index}"
  end
end
