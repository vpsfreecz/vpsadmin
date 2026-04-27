# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/network/register'

RSpec.describe NodeCtld::Commands::Network::Register do
  let(:driver) { build_storage_driver }
  let(:cmd) { described_class.new(driver, {}) }

  it 'is a reversible no-op command' do
    expect(cmd.exec).to eq(ret: :ok)
    expect(cmd.rollback).to eq(ret: :ok)
  end
end
