# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Events::ResourceOperations do
  it 'records a user-owned resource mutation without copying submitted values' do
    event = with_current_context(user: SpecSeed.user) do |session|
      described_class.updated!(
        SpecSeed.user,
        changed_fields: %i[password login password]
      ).tap do |created_event|
        expect(created_event.user).to eq(SpecSeed.user)
        expect(created_event.ip_addr).to eq(session.client_ip_addr || session.api_ip_addr)
      end
    end

    expect(event).to be_persisted
    expect(event.event_type).to eq('resource.updated')
    expect(event.source_class).to eq('User')
    expect(event.source_id).to eq(SpecSeed.user.id)
    expect(event.parameters).to include(
      'resource_type' => 'User',
      'resource_id' => SpecSeed.user.id,
      'action' => 'updated',
      'actor_user_id' => SpecSeed.user.id,
      'actor_user_login' => SpecSeed.user.login,
      'changed_fields' => %w[login password]
    )
    expect(event.payload_json).not_to include(SpecSeed::PASSWORD)
  end

  it 'records an administrator mutation of a system resource as a system event' do
    event = with_current_context(user: SpecSeed.admin) do
      described_class.created!(SpecSeed.node)
    end

    expect(event).to be_persisted
    expect(event.user).to be_nil
    expect(event.source_class).to eq('Node')
    expect(event.source_id).to eq(SpecSeed.node.id)
    expect(event.parameters).to include(
      'resource_type' => 'Node',
      'resource_id' => SpecSeed.node.id,
      'action' => 'created',
      'actor_user_id' => SpecSeed.admin.id
    )
  end

  it 'does not make a support actor the owner of a system resource event' do
    event = with_current_context(user: SpecSeed.support) do
      described_class.updated!(SpecSeed.node, changed_fields: %i[active])
    end

    expect(event).to be_persisted
    expect(event.user).to be_nil
    expect(event.parameters).to include(
      'actor_user_id' => SpecSeed.support.id,
      'changed_fields' => %w[active]
    )
  end

  it 'publishes all generic resource event types in the event catalog' do
    expect(described_class::ACTIONS.map { |action| "resource.#{action}" })
      .to all(satisfy { |event_type| VpsAdmin::API::Events.type_for(event_type) })
  end
end
