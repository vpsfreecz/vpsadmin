require_relative 'lockable'

class UserNamespaceMap < ActiveRecord::Base
  belongs_to :user_namespace
  has_many :vpses
  has_many :user_namespace_map_entries, dependent: :delete_all

  include Lockable

  def self.create_direct!(userns, label)
    self.transaction do
      create_chained!(userns, label)
    end
  end

  def self.create_chained!(userns, label)
    create!(
      user_namespace: userns,
      label: label,
    )
  end

  def in_use?
    vpses.any?
  end
end
