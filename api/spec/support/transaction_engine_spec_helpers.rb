# frozen_string_literal: true

require 'base64'
require 'json'
require 'openssl'

module TransactionEngineSpecHelpers
  def with_current_context(user: SpecSeed.admin)
    previous_user = ::User.current
    previous_session = ::UserSession.current

    ::User.current = user
    ::UserSession.current = ::UserSession.create!(
      user:,
      auth_type: 'basic',
      api_ip_addr: '127.0.0.1',
      client_version: 'RSpec'
    )

    yield(::UserSession.current)
  ensure
    ::User.current = previous_user
    ::UserSession.current = previous_session
  end

  def lock_transaction_signer!
    TransactionKeyHelpers.reset_transaction_signer!
  end

  def unlock_transaction_signer!
    TransactionKeyHelpers.install_encrypted_transaction_key!
    TransactionKeyHelpers.reset_transaction_signer!
    ::VpsAdmin::API::TransactionSigner.unlock(TransactionKeyHelpers::TEST_PASSPHRASE)
  end

  def signer_private_key
    ::VpsAdmin::API::TransactionSigner.instance.instance_variable_get(:@key)
  end

  def verify_signature_base64!(data, signature)
    digest = OpenSSL::Digest.new('SHA256')

    expect(
      signer_private_key.public_key.verify(digest, Base64.decode64(signature), data)
    ).to be(true)
  end

  def complete_chain_operation!(chain)
    chain.update!(state: :done)
    VpsAdmin::API::Events::OperationLifecycle.emit_succeeded!(chain)
  end

  def fail_chain_operation!(chain, state: :failed)
    chain.update!(state:)
    VpsAdmin::API::Events::OperationLifecycle.emit_failed!(chain, state:)
  end

  def expect_deferred_event!(chain, event_type)
    expect(Event.where(event_type:)).to be_empty

    expect(deferred_result_events(chain).count do |descriptor|
      descriptor['event_type'] == event_type
    end).to eq(1)
  end

  def deferred_result_events(chain)
    chain.transactions
         .where(handle: Transactions::Utils::NoOp.t_type)
         .order(id: :desc)
         .filter_map do |transaction|
           JSON.parse(transaction.input).dig('input', 'result_events')
         rescue JSON::ParserError
           nil
         end.flatten
  end

  def expect_completed_event!(event_type, user:)
    event = Event.where(event_type:, user:).order(:id).last
    expect(event).to be_present
    expect(event).to be_routed_routing_state

    delivery = event.event_deliveries.sole
    expect(delivery).to be_released_state
    expect(delivery.mail_log).to be_present

    event
  end

  def expect_resource_event!(action, object, operation: nil)
    resource_name =
      VpsAdmin::API::Events::ResourceOperations.resource_name_for(object)
    event = Event.where(
      event_type: "#{resource_name}.#{action}",
      source_class: object.class.base_class.name,
      source_id: object.id
    ).sole
    expect(event.parameters).to include(
      'resource_name' => resource_name,
      'resource_id' => object.id,
      'resource_action' => action.to_s,
      'resource_schema_version' => 1
    )

    if operation
      expect(event.parameters).to include('operation_id' => operation.id)
      expect(event.parameters).not_to have_key('operation_attempt')
    else
      expect(event.parameters).not_to have_key('operation_id')
    end

    event
  end
end

RSpec.configure do |config|
  config.include TransactionEngineSpecHelpers
end
