# frozen_string_literal: true

require 'spec_helper'

class FakeNetworkMonitor
  attr_reader :listed_with

  def initialize(rows)
    @rows = rows
  end

  def list(params)
    @listed_with = params
    @rows
  end
end

RSpec.describe VpsAdmin::CLI::Commands::NetworkTop do
  def command_with(opts: {}, global_opts: {})
    described_class.allocate.tap do |command|
      command.instance_variable_set(:@opts, { unit: :bits }.merge(opts))
      command.instance_variable_set(:@global_opts, global_opts)
    end
  end

  it 'formats bytes as bits per second by default' do
    command = command_with

    expect(command.send(:unitize_param, :bytes, 1024, 1)).to eq('8.0k')
  end

  it 'formats bytes as bytes per second when requested' do
    command = command_with(opts: { unit: :bytes })

    expect(command.send(:unitize_param, :bytes, 1536, 1)).to eq('1.5k')
  end

  it 'fetches monitor rows with sort, limit, filters, and includes' do
    monitor = FakeNetworkMonitor.new([])
    api = FakeRecord.new(network_interface_monitor: monitor)
    command = command_with(opts: { limit: 3, user: 55 })

    command.instance_variable_set(:@api, api)
    command.instance_variable_set(:@sort_desc, true)
    command.instance_variable_set(:@sort_param, :bytes)

    expect(command.send(:fetch)).to eq([])
    expect(monitor.listed_with).to eq(
      order: '-bytes',
      meta: { includes: 'network_interface' },
      limit: 3,
      user: 55
    )
  end

  it 'moves the selected sort column' do
    command = command_with
    command.instance_variable_set(:@params, %i[bytes packets])
    command.instance_variable_set(:@sort_param, :bytes)

    command.send(:sort_next, 1)

    expect(command.instance_variable_get(:@sort_param)).to eq(:packets)
    expect(command.instance_variable_get(:@refresh)).to be(true)
  end
end
