# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'requests plugin update chain', requires_plugins: :requests do # rubocop:disable RSpec/DescribeClass
  let(:chain_class) { VpsAdmin::API::Plugins::Requests::TransactionChains::Update }

  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  before do
    ensure_mailer_available!
    SpecSeed.admin.update!(mailer_enabled: true)
  end

  it 'updates attributes, resets state, increments mail id, and threads replies' do
    request = build_change_request!(
      state: :pending_correction,
      last_mail_id: 5,
      full_name: 'Old Name'
    )
    attempts = []

    allow(MailTemplate).to receive(:send_mail!) do |name, opts|
      attempts << [name, opts]
      raise VpsAdmin::API::Exceptions::MailTemplateDoesNotExist, name if opts.dig(:params, :type)

      build_mail_log_double
    end

    chain, = chain_class.fire2(args: [request, {
                                 full_name: 'New Name',
                                 change_reason: 'Updated reason'
                               }])

    request.reload
    expect(request.full_name).to eq('New Name')
    expect(request.change_reason).to eq('Updated reason')
    expect(request.state).to eq('awaiting')
    expect(request.last_mail_id).to eq(6)
    expect(chain.transaction_chain_concerns.pluck(:class_name, :row_id)).to include(
      ['ChangeRequest', request.id]
    )

    user_attempts = attempts.select { |_name, opts| opts[:user] == request.user }
    expect(user_attempts.map(&:first)).to eq(%i[request_action_role_type request_action_role])

    successful = attempts.reject { |_name, opts| opts.dig(:params, :type) }
    successful.each do |(_name, opts)|
      expect(opts[:message_id]).to eq("<vpsadmin-request-#{request.id}-6@vpsadmin.vpsfree.cz>")
      expect(opts[:in_reply_to]).to eq("<vpsadmin-request-#{request.id}-5@vpsadmin.vpsfree.cz>")
      expect(opts[:references]).to eq("<vpsadmin-request-#{request.id}-5@vpsadmin.vpsfree.cz>")
    end
  end
end
