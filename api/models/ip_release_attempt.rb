class IpReleaseAttempt < ApplicationRecord
  belongs_to :ip_release_campaign
  belongs_to :created_by, class_name: 'User'
  belongs_to :transaction_chain
  has_many :ip_release_attempt_addresses
  has_many :ip_release_request_addresses, through: :ip_release_attempt_addresses

  def created_by_login
    created_by&.login
  end

  def ip_count
    ip_release_attempt_addresses.count
  end

  def state
    return preparation if preparation != 'prepared'

    case transaction_chain&.state
    when 'staged', 'queued' then 'running'
    when 'rollbacking' then 'rolling_back'
    when 'done' then 'released'
    when 'failed' then 'failed'
    when 'resolved'
      # Marking a fatal chain resolved alone does not apply its confirmations
      # or free its reservations. Require completed operator reconciliation.
      pending = TransactionConfirmation.joins(:parent_transaction)
                                       .where(transactions: { transaction_chain_id: }, done: false).exists?
      locks = ResourceLock.where(locked_by: transaction_chain).exists?
      released = ip_release_request_addresses.where(release_chain_id: transaction_chain_id)
                                             .where.not(released_at: nil).count
      return 'attention' if pending || locks || (released > 0 && released != ip_count)

      released == ip_count ? 'released' : 'failed'
    else 'attention'
    end
  end

  def active?
    %w[running rolling_back attention].include?(state)
  end

  def record_failure!(error)
    attrs = { preparation: 'preparation_failed' }
    if error.is_a?(ResourceLocked)
      resource_lock = error.get_lock
      attrs.merge!(error: 'resource_locked', blocked_resource: error.model.class.base_class.name,
                   blocked_resource_id: error.model.id,
                   blocked_chain_id: resource_lock&.locked_by_type == 'TransactionChain' ? resource_lock.locked_by_id : nil)
    elsif error.is_a?(ActiveRecord::Deadlocked) || error.is_a?(ActiveRecord::LockWaitTimeout)
      attrs[:error] = 'database_busy'
    else
      attrs[:error] = error.message
    end
    update!(attrs)
  end
end
