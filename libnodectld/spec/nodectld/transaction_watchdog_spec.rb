# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/transaction_watchdog'

RSpec.describe NodeCtld::TransactionWatchdog do
  subject(:watchdog) { described_class.new(started_at: 100.0) }

  it 'warns at 600 seconds and at 90-second intervals' do
    expect(watchdog.observe(now: 699.9).warn).to be_falsey
    expect(watchdog.observe(now: 700.0).warn).to be(true)
    expect(watchdog.observe(now: 789.9).warn).to be(false)
    expect(watchdog.observe(now: 790.0).warn).to be(true)
  end

  it 'requests one debug snapshot at 810 seconds' do
    expect(watchdog.observe(now: 909.9).debug).to be_falsey
    expect(watchdog.observe(now: 910.0).debug).to be(true)
    expect(watchdog.observe(now: 920.0).debug).to be(false)
  end

  it 'requests a restart at 900 seconds' do
    expect(watchdog.observe(now: 999.9).restart).to be_falsey
    expect(watchdog.observe(now: 1000.0).restart).to be(true)
  end

  it 'uses a successful transaction poll as the new staleness reference' do
    watchdog.observe(now: 910.0)

    result = watchdog.observe(now: 911.0, last_check: 911.0)

    expect(result.stale_for).to eq(0)
    expect(result.recovered_from).to eq(810.0)
    expect(result).to have_attributes(warn: nil, debug: nil, restart: nil)
  end

  it 'keeps the last known poll time when a health check has no timestamp' do
    watchdog.observe(now: 200.0, last_check: 190.0)

    expect(watchdog.observe(now: 790.0).stale_for).to eq(600.0)
  end
end
