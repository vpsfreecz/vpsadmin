# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::User::CheckLogin do
  let(:user) { SpecSeed.user }
  let(:request) { build_request }

  before do
    user.reload
    user.update!(lockout: false, password_reset: false)
  end

  it 'raises when the account is locked out' do
    user.update!(lockout: true)

    expect do
      described_class.run(user, request)
    end.to raise_error(VpsAdmin::API::Exceptions::OperationError, 'account is locked out, contact support')
  end

  it 'raises when password reset is required' do
    user.update!(password_reset: true)

    expect do
      described_class.run(user, request)
    end.to raise_error(VpsAdmin::API::Exceptions::OperationError, 'password reset required')
  end

  it 'can explicitly allow the password-reset continuation step' do
    user.update!(password_reset: true)

    expect(described_class.run(user, request, allow_password_reset: true)).to be_nil
  end

  it 'does not reject suspension by itself' do
    user.update!(object_state: :suspended)
    mark_user_paid_until!(user)

    expect(described_class.run(user, request)).to be_nil
  end

  it 'executes hooks for allowed users' do
    op = described_class.new
    seen = nil

    op.connect_hook(:check_login) do |ret, user:, request:|
      seen = { user: user, request: request }
      ret
    end

    expect(op.run(user, request)).to be_nil
    expect(seen).to eq(user: user, request: request)
  end
end
