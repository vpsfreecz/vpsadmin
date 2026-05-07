# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/thread_pool'

RSpec.describe NodeCtld::ThreadPool do
  it 'runs all queued blocks' do
    results = Queue.new
    pool = described_class.new(2)

    3.times { |i| pool.add { results << i } }
    pool.run

    expect(3.times.map { results.pop }.sort).to eq([0, 1, 2])
  end

  it 'defaults to at least one thread' do
    results = Queue.new
    pool = described_class.new(0)

    pool.add { results << :ran }
    pool.run

    expect(results.pop).to eq(:ran)
  end

  it 'handles more work items than worker threads' do
    results = Queue.new
    pool = described_class.new(2)

    10.times { |i| pool.add { results << i } }
    pool.run

    expect(10.times.map { results.pop }.sort).to eq((0..9).to_a)
  end
end
