# frozen_string_literal: true

RSpec.describe 'Transaction fixtures' do # rubocop:disable RSpec/DescribeClass
  it 'pins the ordinary leased adapter with an open fixture transaction' do
    pool = ActiveRecord::Base.connection_pool
    connection = pool.lease_connection

    expect(connection).to equal(pool.instance_variable_get(:@pinned_connection))
    expect(connection.transaction_open?).to be(true)
    expect(connection.open_transactions).to eq(1)
  end

  it 'keeps the same pinned transaction after support-user request cleanup clears the lease' do
    pool = ActiveRecord::Base.connection_pool
    connection = pool.lease_connection
    transaction = connection.current_transaction

    as(SpecSeed.support) do
      get vpath('/debugs/array_top'), nil, {
        'CONTENT_TYPE' => 'application/json',
        'rack.input' => StringIO.new('{}')
      }
    end

    expect(last_response.status).to eq(403)
    expect(json['status']).to be(false)
    expect(pool.active_connection?).to be_nil
    expect(pool.instance_variable_get(:@pinned_connection)).to equal(connection)

    expect(pool.lease_connection).to equal(connection)
    expect(connection.transaction_open?).to be(true)
    expect(connection.current_transaction).to equal(transaction)
    expect(connection.open_transactions).to eq(1)
  end

  it 'leaves no pin or fixture transaction for an opted-out example', :no_transaction do
    pool = ActiveRecord::Base.connection_pool

    expect(pool.instance_variable_get(:@pinned_connection)).to be_nil

    connection = pool.lease_connection
    expect(connection.transaction_open?).to be(false)
    expect(connection.open_transactions).to eq(0)
  end
end
