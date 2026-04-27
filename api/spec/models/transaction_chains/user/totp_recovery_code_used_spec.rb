# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::User::TotpRecoveryCodeUsed do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  before do
    ensure_user_mail_templates!
    ensure_available_node_status!(SpecSeed.node)
  end

  it 'concerns the user and sends a recovery-code notification mail' do
    user = create_lifecycle_user!
    device = UserTotpDevice.create!(
      user: user,
      label: 'Spec TOTP',
      secret: ROTP::Base32.random_base32,
      recovery_code: 'recovery',
      confirmed: true,
      enabled: true
    )

    chain, = described_class.fire(user, device, nil)

    expect(chain.transaction_chain_concerns.pluck(:class_name, :row_id)).to include(['User', user.id])
    expect(tx_classes(chain)).to include(Transactions::Mail::Send)
    expect(MailLog.joins(:mail_template).exists?(
             mail_templates: { name: 'user_totp_recovery_code_used' }
           )).to be(true)
  end
end
