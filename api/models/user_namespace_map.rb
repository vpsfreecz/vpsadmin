require_relative 'lockable'

class UserNamespaceMap < ActiveRecord::Base
  belongs_to :user_namespace
  has_many :vpses
  has_many :user_namespace_map_entries, dependent: :delete_all

  include Lockable

  def self.create_direct!(userns, label)
    transaction do
      create_chained!(userns, label)
    end
  end

  def self.create_chained!(userns, label)
    create!(
      user_namespace: userns,
      label:
    )
  end

  def in_use?
    vpses.any?
  end

  # @param kind [:uid, :gid]
  # @return [Array<String>]
  def build_map(kind)
    user_namespace_map_entries.to_a.sort do |a, b|
      a.id <=> b.id
    end.select do |entry|
      entry.kind.to_sym == kind
    end.map(&:to_os)
  end
end
