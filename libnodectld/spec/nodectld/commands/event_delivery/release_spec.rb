# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/event_delivery/release'

RSpec.describe NodeCtld::Commands::EventDelivery::Release do
  def insert_event
    sql_insert('events', {
      event_type: 'user.test_notification',
      category: 'user',
      severity: 0,
      subject: 'release command notification',
      routing_state: 1,
      parameters: '{}',
      created_at: Time.now.utc,
      updated_at: Time.now.utc
    })
  end

  def insert_delivery(action)
    sql_insert('event_deliveries', {
      event_id: insert_event,
      action: action,
      target_kind: 0,
      target_value: 'default',
      target_label: 'Default recipient',
      state: described_class::PREPARED_STATE,
      attempt_count: 0,
      created_at: Time.now.utc,
      updated_at: Time.now.utc
    })
  end

  it 'publishes wakeups using string delivery actions' do
    exchange = stub_node_bunny
    email_id = insert_delivery('email')
    webhook_id = insert_delivery('webhook')
    published = []
    command = Struct.new(:progress, :log_type).new(0, nil)
    cmd = described_class.new(command, 'delivery_ids' => [email_id, webhook_id])

    allow(NodeCtld::NodeBunny).to receive(:publish_wait) do |published_exchange, payload, **opts|
      published << [published_exchange, JSON.parse(payload), opts]
    end

    expect(cmd.exec).to eq(ret: :ok)
    cmd.on_save(shared_db)
    cmd.post_save

    expect(sql_value('SELECT state FROM event_deliveries WHERE id = ?', email_id)).to eq(
      described_class::RELEASED_STATE
    )
    expect(sql_value('SELECT state FROM event_deliveries WHERE id = ?', webhook_id)).to eq(
      described_class::RELEASED_STATE
    )
    expect(published.map { |row| row[0] }).to all(eq(exchange))
    expect(published.map { |row| row[1].fetch('delivery_id') }).to contain_exactly(email_id, webhook_id)
    expect(published.map { |row| row[1].fetch('action') }).to contain_exactly('email', 'webhook')
    expect(published.map { |row| row[2].fetch(:routing_key) }).to contain_exactly(
      'delivery.email',
      'delivery.webhook'
    )
  end
end
