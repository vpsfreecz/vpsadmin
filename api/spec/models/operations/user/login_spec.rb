# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::User::Login do
  let(:user) { SpecSeed.user }
  let(:request) { build_request(ip: '198.51.100.50') }

  before do
    user.update!(
      login_count: 2,
      current_login_at: Time.at(1_600_000_000),
      current_login_ip: '192.0.2.10',
      last_login_at: Time.at(1_500_000_000),
      last_login_ip: '192.0.2.9',
      password_reset: false,
      lockout: false
    )
  end

  it 'calls CheckLogin and records successful login state' do
    allow(VpsAdmin::API::Operations::User::CheckLogin).to receive(:run).and_call_original

    described_class.run(user, request)

    expect(VpsAdmin::API::Operations::User::CheckLogin).to have_received(:run).with(user, request)

    user.reload
    expect(user.login_count).to eq(3)
    expect(user.last_login_at).to eq(Time.at(1_600_000_000))
    expect(user.last_login_ip).to eq('192.0.2.10')
    expect(user.current_login_at).not_to be_nil
    expect(user.current_login_ip).to eq('198.51.100.50')
    expect(User.current).to eq(user)
  end

  it 'locks the account when password reset is pending' do
    user.update!(password_reset: true, lockout: false)

    described_class.run(user, request)

    expect(user.reload.lockout).to be(true)
  end

  context 'with payments plugin login gate', requires_plugins: :payments do
    it 'blocks non-active users with unpaid payment accounts' do
      user.update!(object_state: :suspended)
      user.user_account.update!(paid_until: nil)

      expect do
        described_class.run(user, request)
      end.to raise_error(
        VpsAdmin::API::Exceptions::OperationError,
        'waiting for payment of the membership fee'
      )
    end

    it 'does not block active users with unpaid payment accounts' do
      user.update!(object_state: :active)
      user.user_account.update!(paid_until: nil)

      expect { described_class.run(user, request) }.not_to raise_error
    end

    it 'does not block non-active users whose accounts are paid' do
      user.update!(object_state: :suspended)
      user.user_account.update!(paid_until: 1.month.from_now)

      expect { described_class.run(user, request) }.not_to raise_error
    end
  end
end
