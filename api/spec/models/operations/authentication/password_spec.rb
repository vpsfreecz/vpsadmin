# frozen_string_literal: true

require 'spec_helper'
require 'timeout'

RSpec.describe VpsAdmin::API::Operations::Authentication::Password do
  let(:op) { described_class.new }
  let(:user) { SpecSeed.user }
  let(:request) do
    build_request(
      ip: '198.51.100.42',
      user_agent: 'RSpec/Password',
      extra_env: { 'HTTP_X_REAL_IP' => '203.0.113.9' }
    )
  end

  before do
    next if RSpec.current_example.metadata[:isolated_lifecycle_user]

    SpecSeed.set_password!(user, 'secret')
    user.update!(
      enable_multi_factor_auth: false,
      password_reset: false,
      lockout: false,
      enable_basic_auth: true
    )
    stub_ptr_lookup!(op, ptr: 'ptr.example.test')
    allow(op).to receive(:resolve_password_change_ptr).and_return('password.example.test')
  end

  around do |example|
    if example.metadata[:no_transaction]
      node = SpecSeed.node
      node_attributes = node.attributes.slice(
        'active',
        'maintenance_lock',
        'maintenance_lock_reason',
        'updated_at'
      )
      node_status_attributes = NodeCurrentStatus.find_by(node:)&.attributes
    end

    example.run
  ensure
    if node
      NodeCurrentStatus.where(node_id: node.id).delete_all
      NodeCurrentStatus.create!(node_status_attributes) if node_status_attributes
      node.reload.update_columns(node_attributes)
    end
  end

  def wait_for_blocking_query(connection_id, *fragments)
    Timeout.timeout(5) do
      loop do
        info = ActiveRecord::Base.connection.select_value(
          ApplicationRecord.sanitize_sql_array(
            ['SELECT INFO FROM information_schema.PROCESSLIST WHERE ID = ?', connection_id]
          )
        )
        break if info && fragments.all? { |fragment| info.include?(fragment) }

        sleep(0.01)
      end
    end
  end

  it 'returns nil for an unknown login' do
    expect(op.run('missing-user', 'secret', request:)).to be_nil
  end

  it 'returns an unauthenticated result for a wrong password' do
    result = op.run(user.login, 'wrong', request:)

    expect(result).not_to be_authenticated
    expect(result).not_to be_complete
    expect(result.token).to be_nil
  end

  it 'returns a complete authenticated result for a correct password' do
    result = op.run(user.login, 'secret', request:)

    expect(result).to be_authenticated
    expect(result).to be_complete
    expect(result.user).to eq(user)
    expect(result.token).to be_nil
    expect(result.authentication_generation).to eq(user.authentication_generation)
  end

  it 'authenticates suspended users' do
    user.update!(object_state: :suspended, lockout: false, password_reset: false)
    record_requested_user_state!(user, :suspended)

    result = op.run(user.login, 'secret', request:)

    expect(result).to be_authenticated
    expect(result).to be_complete
    expect(result.user).to eq(user)
  end

  it 'rejects a correct password after destructive lifecycle state is requested' do
    record_requested_user_state!(user, :soft_delete)

    expect do
      expect(op.run(user.login, 'secret', request:)).to be_nil
    end.not_to change(AuthToken, :count)
  end

  it 'publishes a destructive lifecycle request after in-flight token issuance',
     :isolated_lifecycle_user, :no_transaction do
    unlock_transaction_signer!
    ensure_user_mail_templates!
    ensure_available_node_status!(SpecSeed.node)
    target = create_lifecycle_user!
    target.update!(enable_multi_factor_auth: true)
    create_totp_device!(user: target)

    lifecycle_checked = Queue.new
    continue_authentication = Queue.new
    lifecycle_connection = Queue.new
    authentication_thread = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        owner = Thread.current
        callback = lambda do |_name, _start, _finish, _id, payload|
          sql = payload[:sql]
          next unless Thread.current == owner && sql.include?('FROM `object_states`')

          lifecycle_checked << true
          continue_authentication.pop
        end

        ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
          described_class.run(target.login, 'secret123')
        end
      end
    end

    Timeout.timeout(5) { lifecycle_checked.pop }
    lifecycle_thread = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        User.current = SpecSeed.admin
        lifecycle_connection << ActiveRecord::Base.connection.select_value(
          'SELECT CONNECTION_ID()'
        )
        User.find(target.id).set_object_state(
          :soft_delete,
          reason: 'concurrent authentication spec',
          user: SpecSeed.admin
        )
      ensure
        User.current = nil
      end
    end

    connection_id = Timeout.timeout(5) { lifecycle_connection.pop }
    wait_for_blocking_query(connection_id, 'FROM `users`', 'FOR UPDATE')
    lifecycle_blocked = lifecycle_thread.alive?
    continue_authentication << true
    result = authentication_thread.value
    lifecycle_chain = lifecycle_thread.value

    expect(lifecycle_blocked).to be(true)
    expect(result.token).to be_mfa
    expect(target.reload.object_state).to eq('active')
    expect(target.current_object_state&.state).to eq('soft_delete')
  ensure
    continue_authentication << true if authentication_thread&.alive?
    authentication_thread&.join(5)
    lifecycle_thread&.join(5)
    lifecycle_chains = [lifecycle_chain].compact
    if target
      lifecycle_chains.concat(
        TransactionChain.joins(:transaction_chain_concerns).where(
          transaction_chain_concerns: {
            class_name: 'User',
            row_id: target.id
          }
        )
      )
    end
    lifecycle_chains.uniq(&:id).each do |chain|
      next unless TransactionChain.exists?(chain.id)

      transactions = Transaction.where(transaction_chain_id: chain.id)
      MailLog.where(transaction_id: transactions.select(:id)).destroy_all
      TransactionConfirmation.where(transaction_id: transactions.select(:id)).delete_all
      transactions.delete_all
      ResourceLock.where(locked_by: chain).delete_all
      chain.transaction_chain_concerns.delete_all
      chain.destroy!
    end
    AuthToken.where(user_id: target.id).destroy_all if target
    UserTotpDevice.where(user_id: target.id).delete_all if target
    PasswordChangeLog.where(user_id: target.id).delete_all if target
    ObjectState.where(class_name: 'User', row_id: target.id).delete_all if target
    target&.delete if target && User.unscoped.exists?(target.id)
  end

  it 'returns an MFA token when MFA is required and enabled' do
    create_totp_device!(user:)
    user.update!(enable_multi_factor_auth: true)

    result = op.run(user.login, 'secret', request:)

    expect(result).to be_authenticated
    expect(result).not_to be_complete
    expect(result.token).to be_mfa
    expect(result.token.authentication_generation).to eq(user.authentication_generation)
    expect(result.token.client_ip_addr).to eq('203.0.113.9')
  end

  it 'does not create an MFA token when multi-factor handling is disabled' do
    create_totp_device!(user:)
    user.update!(enable_multi_factor_auth: true)

    result = op.run(user.login, 'secret', multi_factor: false, request:)

    expect(result).to be_authenticated
    expect(result).not_to be_complete
    expect(result.token).to be_nil
  end

  it 'returns a reset-password token when no MFA is required' do
    user.update!(password_reset: true)

    result = op.run(user.login, 'secret', request:)

    expect(result).to be_authenticated
    expect(result).to be_complete
    expect(result).to be_reset_password
    expect(result.token).to be_reset_password
  end

  it 'copies request metadata into created auth tokens' do
    user.update!(password_reset: true)

    token = op.run(user.login, 'secret', request:).token

    expect(token.api_ip_addr).to eq('198.51.100.42')
    expect(token.api_ip_ptr).to eq('ptr.example.test')
    expect(token.client_ip_addr).to eq('203.0.113.9')
    expect(token.client_ip_ptr).to eq('ptr.example.test')
    expect(token.user_agent.agent).to eq('RSpec/Password')
    expect(token.client_version).to eq('RSpec/Password')
  end

  it 'upgrades the password hash when an old provider matches' do
    user.update!(
      password_version: :md5,
      password: VpsAdmin::API::CryptoProviders::Md5.encrypt(user.login, 'secret')
    )
    PasswordChangeLog.where(user:).delete_all
    session = create_open_session!(user:, auth_type: :basic)
    UserSession.current = session

    result = op.run(user.login, 'secret', request:)

    expect(result).to be_authenticated
    expect(user.reload.password_version).to eq('bcrypt')
    expect(VpsAdmin::API::CryptoProviders::Bcrypt.matches?(user.password, user.login, 'secret')).to be(true)
    expect(PasswordChangeLog.find_by!(user:)).to have_attributes(
      source: 'other',
      user_session_id: session.id,
      client_ip_addr: session.client_ip_addr,
      client_ip_ptr: session.client_ip_ptr,
      user_agent_id: session.user_agent_id,
      user_session_owned_by_user: true
    )
  end

  it 'records request metadata for a sessionless password hash upgrade' do
    user.update!(
      password_version: :md5,
      password: VpsAdmin::API::CryptoProviders::Md5.encrypt(user.login, 'secret')
    )
    PasswordChangeLog.where(user:).delete_all
    UserSession.current = nil

    result = op.run(user.login, 'secret', request:)

    expect(result).to be_authenticated
    expect(PasswordChangeLog.find_by!(user:)).to have_attributes(
      source: 'other',
      user_session_id: nil,
      client_ip_addr: '203.0.113.9',
      client_ip_ptr: 'password.example.test'
    )
    expect(PasswordChangeLog.find_by!(user:).user_agent.agent).to eq('RSpec/Password')
  end
end
