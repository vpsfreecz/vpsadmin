# frozen_string_literal: true

RSpec.describe ApiAppHelper do
  before { header 'Accept', 'application/json' }

  def advisory(state)
    ::SecurityAdvisory.create!(name: "Fixture connection #{state}", state:)
  end

  def read_json(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
    expect(last_response.status).to eq(200), last_response.body
    expect(json['status']).to be(true), last_response.body
  end

  def return_secondary(connection)
    return unless connection&.in_use? && connection.owner == Thread.current

    ActiveRecord::Base.connection_pool.checkin(connection)
  end

  it 'keeps a published fixture visible after another pooled connection becomes available' do
    path = vpath('/security_advisories')
    report = advisory(:published)
    pool = ActiveRecord::Base.connection_pool
    secondary = pool.checkout

    read_json "#{path}/#{report.id}"
    pool.checkin(secondary)
    read_json "#{path}/#{report.id}"
    expect(json.dig('response', 'security_advisory', 'id')).to eq(report.id)
  ensure
    return_secondary(secondary)
  end

  it 'keeps hidden-parent filters valid without exposing the retracted fixture' do
    path = vpath('/security_advisory_cves')
    report = advisory(:retracted)
    pool = ActiveRecord::Base.connection_pool
    secondary = pool.checkout
    params = {
      security_advisory_cve: { security_advisory: report.id },
      _meta: { count: true, includes: 'security_advisory' }
    }

    read_json path, params
    pool.checkin(secondary)
    read_json path, params
    expect(json.dig('response', 'security_advisory_cves')).to eq([])
    expect(json.dig('response', '_meta', 'total_count')).to eq(0)
  ensure
    return_secondary(secondary)
  end

  it 'retains ordinary request connection cleanup for committed fixtures', :no_transaction do
    show_path = vpath('/security_advisories')
    cve_path = vpath('/security_advisory_cves')
    published = advisory(:published)
    retracted = advisory(:retracted)
    pool = ActiveRecord::Base.connection_pool
    secondary = pool.checkout

    read_json "#{show_path}/#{published.id}"
    expect(pool.active_connection?).to be_nil
    pool.checkin(secondary)
    expect(pool.lease_connection).to equal(secondary)
    read_json "#{show_path}/#{published.id}"
    read_json cve_path,
              security_advisory_cve: { security_advisory: retracted.id },
              _meta: { count: true, includes: 'security_advisory' }
    expect(json.dig('response', 'security_advisory_cves')).to eq([])
    expect(pool.active_connection?).to be_nil
  ensure
    return_secondary(secondary)
    ::SecurityAdvisory.where(id: [published&.id, retracted&.id].compact).find_each(&:destroy!)
  end

  it 'does not retain another thread\'s connection or transaction' do
    app
    pool = ActiveRecord::Base.connection_pool
    fixture_connection = pool.active_connection?

    worker = Thread.new do
      pool.with_connection do |connection|
        connection.transaction do
          ActiveRecord::Base.connection_handler.clear_active_connections!
          [connection, pool.active_connection?, connection.transaction_open?]
        end
      end
    end
    connection, active_connection, transaction_open = worker.value

    expect(connection).not_to equal(fixture_connection)
    expect(active_connection).to be_nil
    expect(transaction_open).to be(true)
    expect(connection.owner).to be_nil
    expect(pool.active_connection?).to equal(fixture_connection)
  ensure
    worker&.join
  end
end
