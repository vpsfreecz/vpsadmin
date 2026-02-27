# frozen_string_literal: true

module LifetimesResourceHelpers
  def lifetimes_states
    VpsAdmin::API::Lifetimes::STATES.map(&:to_s)
  end

  def lifetimes_transition_supported?(from, to)
    from = from.to_s
    to = to.to_s
    return false if from == to

    states = lifetimes_states
    from_idx = states.index(from)
    to_idx = states.index(to)
    hard_delete_idx = states.index('hard_delete')

    raise "Unknown lifetime state: #{from}" if from_idx.nil?
    raise "Unknown lifetime state: #{to}" if to_idx.nil?

    enter = to_idx > from_idx
    return false if !enter && hard_delete_idx && from_idx >= hard_delete_idx

    true
  end

  def lifetimes_transition_supported_for?(model, from, to)
    return false unless lifetimes_transition_supported?(from, to)

    changes = VpsAdmin::API::Lifetimes::Private.state_changes(model) || {}
    enter_chain = changes.dig(to.to_sym, :enter)
    enter_chain != TransactionChains::Lifetimes::NotImplemented
  end
end

RSpec.configure do |config|
  config.include LifetimesResourceHelpers
end
