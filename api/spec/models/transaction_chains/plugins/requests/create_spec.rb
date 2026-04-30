# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'requests plugin create chain', requires_plugins: :requests do # rubocop:disable RSpec/DescribeClass
  let(:chain_class) { VpsAdmin::API::Plugins::Requests::TransactionChains::Create }

  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  before do
    ensure_mailer_available!
    SpecSeed.admin.update!(mailer_enabled: true)
  end

  it 'concerns the request and sends user/admin mail with type fallback' do
    admin2 = create_lifecycle_user!(login: 'plugin-request-admin')
    admin2.update!(level: 99, mailer_enabled: true)
    disabled_admin = create_lifecycle_user!(login: 'plugin-request-muted')
    disabled_admin.update!(level: 99, mailer_enabled: false)
    request = build_registration_request!(last_mail_id: 3)
    attempts = []

    allow(MailTemplate).to receive(:send_mail!) do |name, opts|
      attempts << [name, opts]
      raise VpsAdmin::API::Exceptions::MailTemplateDoesNotExist, name if opts.dig(:params, :type)

      build_mail_log_double
    end

    chain, = chain_class.fire2(args: [request])

    expect(chain.transaction_chain_concerns.pluck(:class_name, :row_id)).to include(
      ['RegistrationRequest', request.id]
    )
    expect(tx_classes(chain)).to all(eq(Transactions::Mail::Send))

    user_attempts = attempts.select { |_name, opts| opts[:user] == request.user }
    expect(user_attempts.map(&:first)).to eq(%i[request_action_role_type request_action_role])

    admin_attempts = attempts.select { |_name, opts| opts.dig(:params, :role) == 'admin' }
    successful_admins = admin_attempts.reject { |_name, opts| opts.dig(:params, :type) }
    expect(successful_admins.map { |_name, opts| opts[:user] }).to contain_exactly(SpecSeed.admin, admin2)
    expect(successful_admins.map { |_name, opts| opts[:user] }).not_to include(disabled_admin)

    attempts.each do |(_name, opts)|
      expect(opts[:message_id]).to eq("<vpsadmin-request-#{request.id}-3@vpsadmin.vpsfree.cz>")
      expect(opts[:vars]).to include(request: request, r: request)
    end
  end

  it 'allows an empty chain when every template is missing' do
    request = build_registration_request!
    allow(MailTemplate).to receive(:send_mail!) do |name, _opts|
      raise VpsAdmin::API::Exceptions::MailTemplateDoesNotExist, name
    end

    chain, = chain_class.fire2(args: [request])

    expect(chain).to be_nil
  end
end
