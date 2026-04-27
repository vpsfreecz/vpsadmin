# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::User::ReportFailedLogins do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  before do
    ensure_user_mail_templates!
    ensure_available_node_status!(SpecSeed.node)
  end

  it 'concerns every affected user, sends one mail per group, and marks attempts reported' do
    user_a = create_lifecycle_user!
    user_b = create_lifecycle_user!
    attempts_a = [
      create_failed_login!(user: user_a, created_at: 2.minutes.ago),
      create_failed_login!(user: user_a, created_at: 1.minute.ago)
    ]
    attempts_b = [create_failed_login!(user: user_b)]

    chain, = described_class.fire(
      user_a => [attempts_a],
      user_b => [attempts_b]
    )

    expect(chain.transaction_chain_concerns.pluck(:class_name, :row_id)).to include(
      ['User', user_a.id],
      ['User', user_b.id]
    )
    expect(tx_classes(chain).count(Transactions::Mail::Send)).to eq(2)
    expect(UserFailedLogin.where(id: attempts_a.concat(attempts_b).map(&:id)).where(reported_at: nil)).to be_empty
  end
end
