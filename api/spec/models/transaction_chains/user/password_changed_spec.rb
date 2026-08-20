# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::User::PasswordChanged do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  before do
    ensure_user_mail_templates!
    ensure_available_node_status!(SpecSeed.node)
    SysConfig.find_or_create_by!(category: 'core', name: 'support_mail').update!(
      value: 'support@example.test'
    )
  end

  it 'concerns the user and sends a plain security notification' do
    user = create_lifecycle_user!
    request = build_request(
      ip: '192.0.2.40',
      user_agent: 'Password changed spec'
    )

    chain, = described_class.fire(user, request)

    expect(chain.transaction_chain_concerns.pluck(:class_name, :row_id)).to include(
      ['User', user.id]
    )
    expect(tx_classes(chain)).to include(Transactions::Mail::Send)

    mail = MailLog.joins(:mail_template).find_by!(
      mail_templates: { name: 'user_password_changed' }
    )
    expect(mail.user).to eq(user)
    expect(mail.to).to include(user.email)
    expect(mail.text_plain).to include(
      user.login,
      '192.0.2.40',
      'Password changed spec',
      'support@example.test',
      '(This is an automated mail from vpsAdmin, your reply will be sent to our support)'
    )
    expect(mail.text_html).to be_nil
  end
end
