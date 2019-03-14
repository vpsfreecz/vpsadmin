class UserNamespaceMapEntry < ActiveRecord::Base
  belongs_to :user_namespace_map
  enum kind: %i(uid gid)

  validates :vps_id, :ns_id, numericality: {
    only_integer: true,
    greater_than_or_equal_to: 0,
  }
  validates :count, numericality: {
    only_integer: true,
    greater_than: 0,
  }
  validate :ids_in_range

  def to_user
    "#{vps_id}:#{ns_id}:#{count}"
  end

  def to_os
    "#{vps_id}:#{user_namespace_map.user_namespace.offset + ns_id}:#{count}"
  end

  protected
  def ids_in_range
    max_size = user_namespace_map.user_namespace.size

    if ns_id >= max_size
      errors.add(:ns_id, "ns_id cannot be greater or equal than #{max_size}")

    elsif ns_id + count > max_size
      errors.add(:count, "for ns_id=#{ns_id}, maximum count value is "+
                 "#{max_size - ns_id}")
    end
  end
end
