require_relative 'confirmable'
require_relative 'lockable'

class StoragePool < ApplicationRecord
  belongs_to :uuid, dependent: :delete
  belongs_to :node

  include Confirmable
  include Lockable

  def self.take_by_node!(node)
    where(node:).take!
  end
end
