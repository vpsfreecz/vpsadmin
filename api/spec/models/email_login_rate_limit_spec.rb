require 'spec_helper'
require 'timeout'

RSpec.describe EmailLoginRateLimit do
  let(:user) { SpecSeed.user }
  let(:request) { build_request(ip: '198.51.100.199') }
  let(:now) { Time.utc(2026, 9, 14, 12) }

  before { allow(Time).to receive(:now).and_return(now) }

  def consume(target = user, kind = :send, source = request)
    target.with_lock { described_class.with_limits(target, source, kind) { |allowed| allowed } }
  end

  it 'allows five account sends per UTC quarter-hour and keeps the daily count' do
    expect(5.times.map { consume }).to all(be(true))
    expect(consume).to be(false)
    allow(Time).to receive(:now).and_return(now + 15.minutes - 1)
    expect(consume).to be(false)
    allow(Time).to receive(:now).and_return(now + 15.minutes)
    expect(consume).to be(true)
    expect(described_class.find_by!(bucket: "send:user:#{user.id}:86400").count).to eq(6)
  end

  it 'allows twenty account sends per UTC day and resets at midnight' do
    4.times do |quarter|
      allow(Time).to receive(:now).and_return(now + (quarter * 15.minutes))
      expect(5.times.map { consume }).to all(be(true))
    end
    allow(Time).to receive(:now).and_return(now.end_of_day)
    expect(consume).to be(false)
    allow(Time).to receive(:now).and_return(now.tomorrow.beginning_of_day)
    expect(consume).to be(true)
  end

  it 'allows ten account failures per quarter-hour independently of send limits' do
    expect(5.times.map { consume }).to all(be(true))
    expect(10.times.map { consume(user, :failure) }).to all(be(true))
    expect(consume(user, :failure)).to be(false)
    allow(Time).to receive(:now).and_return(now + 15.minutes)
    expect(consume(user, :failure)).to be(true)
  end

  { send: 60, failure: 100 }.each do |kind, maximum|
    it "shares the #{maximum}-#{kind} IP budget across users, separately from other IPs" do
      expect(consume(user, kind)).to be(true)
      bucket = described_class.where('bucket LIKE ?', "#{kind}:ip:%").sole
      bucket.update!(count: maximum - 1)
      expect(consume(SpecSeed.other_user, kind)).to be(true)
      expect(consume(user, kind)).to be(false)
      expect(consume(user, kind, build_request(ip: '198.51.100.200'))).to be(true)
      allow(Time).to receive(:now).and_return(now + 15.minutes)
      expect(consume(user, kind)).to be(true)
    end
  end

  it 'does not consume a budget when the caller does not send or record a failure' do
    user.with_lock { described_class.with_limits(user, request, :send) { false } }
    expect(described_class.pluck(:count)).to all(eq(0))
    expect(5.times.map { consume }).to all(be(true))
  end

  it 'serializes the last shared IP slot across independent connections', :no_transaction do
    users = 2.times.map { create_lifecycle_user! }
    expect(consume(users.first)).to be(true)
    bucket = described_class.where('bucket LIKE ?', 'send:ip:%').find_by!(window_start: now)
    bucket.update!(count: 59)
    ready = Queue.new
    start = Queue.new
    workers = users.map do |target|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          consume(User.find(target.id))
        end
      end
    end
    outcomes = Timeout.timeout(10) do
      2.times { ready.pop }
      2.times { start << true }
      workers.map(&:value)
    end
    expect(outcomes.count(true)).to eq(1)
    expect(outcomes.count(false)).to eq(1)
    expect(bucket.reload.count).to eq(60)
  ensure
    workers&.each { |worker| worker.join(1) }
    described_class.where(window_start: [now, now.beginning_of_day]).delete_all
    users&.each(&:delete)
  end
end
