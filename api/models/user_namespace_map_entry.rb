class UserNamespaceMapEntry < ActiveRecord::Base
  belongs_to :user_namespace_map
  enum kind: %i(uid gid)

  validates :ns_id, :host_id, numericality: {
    only_integer: true,
    greater_than_or_equal_to: 0,
  }
  validates :count, numericality: {
    only_integer: true,
    greater_than: 0,
  }
  validate :ids_in_range

  def to_user
    "#{ns_id}:#{host_id}:#{count}"
  end

  def to_os
    "#{ns_id}:#{user_namespace_map.user_namespace.offset + host_id}:#{count}"
  end

  protected
  def ids_in_range
    max_size = user_namespace_map.user_namespace.size

    if host_id >= max_size
      errors.add(:host_id, "host_id cannot be greater or equal than #{max_size}")

    elsif host_id + count > max_size
      errors.add(:count, "for host_id=#{host_id}, maximum count value is "+
                 "#{max_size - host_id}")
    end
  end
end
