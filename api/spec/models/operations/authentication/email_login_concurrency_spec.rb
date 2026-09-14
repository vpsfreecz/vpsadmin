require 'spec_helper'
require 'timeout'

RSpec.describe VpsAdmin::API::EmailLogin, :no_transaction do
  it 'consumes a challenge only once across independent database connections' do
    user = create_lifecycle_user!
    user.update!(enable_new_device_email_verification: true, enable_token_auth: true)
    request = build_request
    context = { 'flow' => 'token' }
    mail = {}
    allow(described_class).to receive(:deliver!) { |_pending, code, _request| mail[:code] = code }
    pending = described_class.start(user, request:, context:,
                                          authentication_generation: user.authentication_generation)
    token = pending.to_s
    ready = Queue.new
    start = Queue.new
    results = Queue.new
    workers = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          begin
            results << described_class.process(token, request: build_request, context:, code: mail[:code])
          rescue described_class::Error => e
            results << e
          end
        end
      end
    end
    Timeout.timeout(10) do
      2.times { ready.pop }
      2.times { start << true }
      workers.each(&:value)
    end
    outcomes = 2.times.map { results.pop }
    expect(outcomes.count { |result| result.is_a?(described_class::Result) && result.success? }).to eq(1)
    expect(outcomes.grep(described_class::Error).map(&:message)).to eq(['email_login_expired'])
  ensure
    workers&.each { |worker| worker.join(1) }
    user&.auth_tokens&.destroy_all
    user&.delete
  end
end
