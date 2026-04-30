# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'requests plugin resolve chain', requires_plugins: :requests do # rubocop:disable RSpec/DescribeClass
  let(:chain_class) { VpsAdmin::API::Plugins::Requests::TransactionChains::Resolve }

  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  before do
    ensure_mailer_available!
    SpecSeed.admin.update!(mailer_enabled: true)
  end

  it 'updates resolution fields, uses fallback templates, and calls the request action' do
    request = build_change_request!(last_mail_id: 2)
    action_call = nil
    attempts = []
    params = { full_name: 'Resolved Name' }

    request.define_singleton_method(:approve) do |chain, action_params|
      action_call = [chain, action_params]
    end

    allow(MailTemplate).to receive(:send_mail!) do |name, opts|
      attempts << [name, opts]
      raise VpsAdmin::API::Exceptions::MailTemplateDoesNotExist, name if opts.dig(:params, :type)

      build_mail_log_double
    end

    chain, = chain_class.fire2(args: [request, :approved, :approve, 'Looks good', params])

    request.reload
    expect(request.state).to eq('approved')
    expect(request.admin).to eq(SpecSeed.admin)
    expect(request.admin_response).to eq('Looks good')
    expect(request.last_mail_id).to eq(3)
    expect(request.full_name).to eq('Resolved Name')
    expect(action_call).to eq([chain, params])

    user_attempts = attempts.select { |_name, opts| opts[:user] == request.user }
    expect(user_attempts.map(&:first)).to eq(
      %i[
        request_resolve_role_type_state
        request_action_role_type
        request_resolve_role_state
      ]
    )

    successful = attempts.reject { |_name, opts| opts.dig(:params, :type) }
    successful.each do |(_name, opts)|
      expect(opts[:message_id]).to eq("<vpsadmin-request-#{request.id}-3@vpsadmin.vpsfree.cz>")
      expect(opts[:in_reply_to]).to eq("<vpsadmin-request-#{request.id}-2@vpsadmin.vpsfree.cz>")
      expect(opts[:references]).to eq("<vpsadmin-request-#{request.id}-2@vpsadmin.vpsfree.cz>")
    end
  end

  it 'skips user mail for ignored requests but still notifies admins' do
    request = build_change_request!(last_mail_id: 1)
    attempts = []

    allow(MailTemplate).to receive(:send_mail!) do |name, opts|
      attempts << [name, opts]
      build_mail_log_double
    end

    chain_class.fire2(args: [request, :ignored, :ignore, 'Duplicate', {}])

    request.reload
    expect(request.state).to eq('ignored')
    expect(request.admin_response).to eq('Duplicate')
    expect(request.last_mail_id).to eq(2)
    expect(attempts.none? { |_name, opts| opts[:user] == request.user }).to be(true)
    expect(attempts.any? { |_name, opts| opts[:user] == SpecSeed.admin }).to be(true)
  end
end
