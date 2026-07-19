# frozen_string_literal: true

require 'spec_helper'
require 'stringio'

RSpec.describe VpsAdmin::API::Tasks::ProgressReporter do
  it 'formats periodic rate and ETA output and a complete created-row count' do
    output = StringIO.new
    now = 0.0
    reporter = described_class.new(
      label: 'node=300 task=kernel',
      io: output,
      clock: -> { now }
    )

    reporter.start(total: 100, attempt: 1)
    now = 4.9
    reporter.advance(processed: 40, created: 1)
    now = 5.0
    reporter.advance(processed: 50, created: 2)
    now = 10.0
    reporter.finish(created: 3)

    expect(output.string).to include('started attempt=1 total=100')
    expect(output.string).to include(
      'progress processed=50/100 percentage=50.0% elapsed=5.0s ' \
      'rate=10.0 rows/s eta=5.0s created=2'
    )
    expect(output.string).to include(
      'complete processed=100/100 percentage=100.0% elapsed=10.0s ' \
      'rate=10.0 rows/s eta=0.0s created=3'
    )
    expect(output.string.scan(': progress ').length).to eq(1)
  end

  it 'formats a zero-row completion without dividing by zero' do
    output = StringIO.new
    reporter = described_class.new(label: 'empty', io: output, clock: -> { 1.0 })

    reporter.start(total: 0, attempt: 1)
    reporter.finish(created: 0)

    expect(output.string).to include(
      'processed=0/0 percentage=100.0% elapsed=0.0s rate=0.0 rows/s eta=0.0s created=0'
    )
  end

  it 'reports terminal retry exhaustion as a failure' do
    output = StringIO.new
    reporter = described_class.new(label: 'node=300 task=kernel', io: output, clock: -> { 5.0 })

    reporter.start(total: 10, attempt: 4)
    reporter.advance(processed: 10, created: 1)
    reporter.failed(reason: 'history changed')

    expect(output.string).to include('failed processed=10/10')
    expect(output.string).to include('failed reason=history changed')
    expect(output.string).not_to include('retrying')
  end
end
