# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::PasswordRecoveryWorker do
  let(:worker) { described_class.new(poll_interval: 0) }
  let(:request) { build_request(ip: '192.0.2.10', user_agent: 'Recovery worker spec') }

  before do
    SysConfig.find_or_create_by!(category: 'core', name: 'password_recovery_enabled')
             .update!(value: true)
  end

  def enqueue_submission
    PasswordRecoverySubmission.enqueue!(
      identifier: 'member@example.test',
      locale: :en,
      oauth2_client: nil,
      request:
    )
  end

  it 'processes and removes a queued submission outside the HTTP request' do
    queued_submission = enqueue_submission
    allow(VpsAdmin::API::Operations::Authentication::RequestPasswordRecovery)
      .to receive(:run)

    expect(worker.process_next).to eq(:processed)

    expect(PasswordRecoverySubmission.exists?(queued_submission.id)).to be(false)
    expect(VpsAdmin::API::Operations::Authentication::RequestPasswordRecovery)
      .to have_received(:run) do |identifier, **kwargs|
        expect(identifier).to eq('member@example.test')
        expect(kwargs[:locale]).to eq(:en)
        expect(kwargs[:oauth2_client]).to be_nil
        expect(kwargs[:request].ip).to eq('192.0.2.10')
        expect(kwargs[:request].user_agent).to eq('Recovery worker spec')
        expect(kwargs[:submission].id).to eq(queued_submission.id)
      end
  end

  it 'retries failures and discards a submission after the attempt limit' do
    submission = enqueue_submission
    allow(VpsAdmin::API::Operations::Authentication::RequestPasswordRecovery)
      .to receive(:run).and_raise('mail unavailable')

    PasswordRecoverySubmission::MAX_ATTEMPTS.times do |attempt|
      expect do
        expect(worker.process_next).to eq(:error)
      end.to output(/Password recovery worker failed/).to_stderr
      next if attempt + 1 == PasswordRecoverySubmission::MAX_ATTEMPTS

      submission.update_columns(
        processing_started_at: PasswordRecoverySubmission::CLAIM_TIMEOUT.ago - 1.second
      )
    end

    expect(PasswordRecoverySubmission.exists?(submission.id)).to be(false)
  end

  it 'reports an empty queue without doing work' do
    expect(worker.process_next).to eq(:idle)
  end

  it 'discards queued work after the feature is disabled' do
    submission = enqueue_submission
    SysConfig.find_by!(category: 'core', name: 'password_recovery_enabled')
             .update!(value: false)
    allow(VpsAdmin::API::Operations::Authentication::RequestPasswordRecovery)
      .to receive(:run)

    expect(worker.process_next).to eq(:processed)

    expect(PasswordRecoverySubmission.exists?(submission.id)).to be(false)
    expect(VpsAdmin::API::Operations::Authentication::RequestPasswordRecovery)
      .not_to have_received(:run)
  end

  it 'waits with an error backoff after processing failures' do
    delays = []
    running_worker = nil
    running_worker = described_class.new(
      poll_interval: 1,
      error_retry_interval: 17,
      sleep_handler: lambda do |seconds|
        delays << seconds
        running_worker.stop
      end
    )
    allow(running_worker).to receive(:process_next).and_return(:error)

    running_worker.run

    expect(delays).to eq([17])
  end

  it 'waits without querying the queue before its schema exists' do
    connection = ActiveRecord::Base.connection_pool.lease_connection
    allow(connection).to receive(:data_source_exists?).and_return(false)
    allow(PasswordRecoverySubmission).to receive(:claim_next)

    expect(worker.process_next).to eq(:idle)
    expect(PasswordRecoverySubmission).not_to have_received(:claim_next)
  end

  it 'detects its schema after an earlier absent-schema poll' do
    connection = ActiveRecord::Base.connection_pool.lease_connection
    allow(connection).to receive(:data_source_exists?).and_return(false, true)
    allow(PasswordRecoverySubmission).to receive(:claim_next).and_return(nil)

    expect(worker.process_next).to eq(:idle)
    expect(worker.process_next).to eq(:idle)

    expect(connection).to have_received(:data_source_exists?).twice
    expect(PasswordRecoverySubmission).to have_received(:claim_next).once
  end
end
