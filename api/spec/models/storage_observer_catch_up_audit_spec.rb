# frozen_string_literal: true

require 'spec_helper'

RSpec.describe StorageObserverCatchUpAudit do
  def request
    described_class.create!(
      request_id: SecureRandom.uuid, event_type: :requested,
      actor_user_id: 7, actor_user_session_id: 9, actor_user_login: 'admin',
      reason: 'review old-node results', freeze_epoch: 5,
      after_chain_id: 10, page_limit: 100, created_at: Time.current
    )
  end

  it 'retains separate application-readonly request and completion events' do
    requested = request
    result = { settled_chain_ids: [11], blocked_chain_ids: [12],
               settled_intents: 1, blocked_chains: 1 }
    completed = described_class.record_completion!(requested, result)

    expect(completed).to have_attributes(
      request_id: requested.request_id, event_type: 'completed',
      actor_user_id: 7, actor_user_session_id: 9, actor_user_login: 'admin',
      after_chain_id: 10, page_limit: 100
    )
    expect(JSON.parse(completed.result_json)).to include(
      'settled_chain_ids' => [11], 'blocked_chain_ids' => [12]
    )
    expect { requested.update!(reason: 'changed') }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { completed.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it 'leaves the request visible when completion exceeds the audit size bound' do
    requested = request
    huge_result = { blocked_chain_ids: Array.new(100) { 'x' * 400 } }

    expect do
      described_class.record_completion!(requested, huge_result)
    end.to raise_error(ArgumentError, /audit limit/)
    expect(described_class.where(request_id: requested.request_id).pluck(:event_type))
      .to eq(['requested'])
  end
end
