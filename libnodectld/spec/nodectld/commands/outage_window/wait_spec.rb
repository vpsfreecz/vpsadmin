# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/outage_window/wait'

RSpec.describe NodeCtld::Commands::OutageWindow::Wait do
  let(:driver) { build_storage_driver }
  let(:cmd) { described_class.new(driver, {}) }

  it 'returns immediately inside an open window' do
    windows = instance_spy(NodeCtld::Utils::OutageWindow::OutageWindows, open?: true)
    allow(cmd).to receive(:windows).and_return(windows)

    expect(cmd.exec).to eq(ret: :ok)
    expect(windows).not_to have_received(:closest)
    expect(cmd.rollback).to eq(ret: :ok)
  end

  it 'waits for the closest window when no window is open' do
    closest = instance_spy(NodeCtld::Utils::OutageWindow::OutageWindow, wait: nil)
    windows = instance_spy(
      NodeCtld::Utils::OutageWindow::OutageWindows,
      open?: false,
      closest: closest
    )
    allow(cmd).to receive(:windows).and_return(windows)

    expect(cmd.exec).to eq(ret: :ok)
    expect(closest).to have_received(:wait)
  end
end
