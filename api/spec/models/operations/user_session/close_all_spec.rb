# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::UserSession::CloseAll do
  let(:user) { SpecSeed.user }

  it 'closes all open sessions for a user' do
    sessions = 3.times.map { |i| create_open_session!(user:, auth_type: 'token', label: "token #{i}") }

    described_class.run(user)

    expect(sessions.map { |s| s.reload.closed_at }).to all(be_present)
  end

  it 'honors the except list' do
    kept = create_open_session!(user:, auth_type: 'token', label: 'keep')
    closed = create_open_session!(user:, auth_type: 'token', label: 'close')

    described_class.run(user, except: [kept])

    expect(kept.reload.closed_at).to be_nil
    expect(closed.reload.closed_at).not_to be_nil
  end
end
