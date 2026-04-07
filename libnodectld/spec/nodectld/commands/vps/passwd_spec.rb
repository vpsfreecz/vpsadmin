# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/vps/passwd'

RSpec.describe NodeCtld::Commands::Vps::Passwd do
  let(:driver) do
    instance_double(
      NodeCtld::Command,
      id: 321,
      progress: nil,
      'progress=': nil,
      log_type: :spec
    )
  end
  let(:cmd) do
    described_class.new(
      driver,
      'vps_id' => 101,
      'user' => 'root',
      'password' => 'secret'
    )
  end

  it 'changes the password through the VPS helper and returns ok' do
    vps = instance_spy(NodeCtld::Vps)

    allow(NodeCtld::Vps).to receive(:new).with(101).and_return(vps)

    expect(cmd.exec).to eq(ret: :ok)
    expect(vps).to have_received(:passwd).with('root', 'secret')
  end

  it 'redacts the saved transaction input after persistence' do
    db_class = Class.new do
      def prepared(*); end
    end
    db = instance_double(db_class)

    allow(db).to receive(:prepared)

    cmd.on_save(db)

    expect(db).to have_received(:prepared).with(
      "UPDATE transactions SET input = '{}' WHERE id = ?",
      321
    )
  end

  it 'has a no-op rollback' do
    expect(cmd.rollback).to eq(ret: :ok)
  end
end
