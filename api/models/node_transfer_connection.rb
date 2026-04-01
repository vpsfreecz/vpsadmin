# frozen_string_literal: true

require 'ipaddress'

class NodeTransferConnection < ApplicationRecord
  belongs_to :node_a, class_name: 'Node'
  belongs_to :node_b, class_name: 'Node'

  scope :enabled, -> { where(enabled: true) }

  before_validation :normalize_pair!

  validates :node_a, :node_b, :node_a_ip_addr, :node_b_ip_addr, presence: true
  validates :node_a_id, uniqueness: { scope: :node_b_id }

  validate :nodes_must_differ
  validate :validate_node_a_ip_addr
  validate :validate_node_b_ip_addr

  def self.between(left, right)
    left, right = ordered_nodes(left, right)
    where(node_a: left, node_b: right)
  end

  def self.ordered_nodes(left, right)
    raise ArgumentError, 'both nodes must be present' if left.nil? || right.nil?

    left.id <= right.id ? [left, right] : [right, left]
  end

  def ip_addr_for(node)
    if node.id == node_a_id
      node_a_ip_addr
    elsif node.id == node_b_id
      node_b_ip_addr
    else
      raise ArgumentError, 'node is not part of this transfer connection'
    end
  end

  private

  def normalize_pair!
    return if node_a.nil? || node_b.nil?
    return if node_a_id <= node_b_id

    self.node_a, self.node_b = node_b, node_a
    self.node_a_ip_addr, self.node_b_ip_addr = node_b_ip_addr, node_a_ip_addr
  end

  def nodes_must_differ
    return if node_a_id.nil? || node_b_id.nil?
    return unless node_a_id == node_b_id

    errors.add(:node_b, 'must differ from node_a')
  end

  def validate_node_a_ip_addr
    validate_host_ipv4(:node_a_ip_addr)
  end

  def validate_node_b_ip_addr
    validate_host_ipv4(:node_b_ip_addr)
  end

  def validate_host_ipv4(attr)
    value = public_send(attr)
    return if value.blank?

    ip = IPAddress.parse(value)

    unless ip.ipv4? && ip.prefix == 32
      errors.add(attr, 'must be a plain IPv4 host address')
    end
  rescue ArgumentError, IPAddress::InvalidAddressError
    errors.add(attr, 'not a valid IPv4 address')
  end
end
