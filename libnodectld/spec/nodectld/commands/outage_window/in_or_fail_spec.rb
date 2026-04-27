# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/outage_window/in_or_fail'

RSpec.describe NodeCtld::Commands::OutageWindow::InOrFail do
  let(:driver) { build_storage_driver }
  let(:cmd) { described_class.new(driver, {}) }

  it 'succeeds inside an open window' do
    windows = instance_double(NodeCtld::Utils::OutageWindow::OutageWindows, open?: true)
    allow(cmd).to receive(:windows).and_return(windows)

    expect(cmd.exec).to eq(ret: :ok)
    expect(cmd.rollback).to eq(ret: :ok)
  end

  it 'raises outside an open window' do
    windows = instance_double(NodeCtld::Utils::OutageWindow::OutageWindows, open?: false)
    allow(cmd).to receive(:windows).and_return(windows)

    expect { cmd.exec }.to raise_error('not in a window')
    expect(cmd.rollback).to eq(ret: :ok)
  end
end
