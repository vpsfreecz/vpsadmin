# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/ct'
require 'nodectld/osctl_container'

RSpec.describe NodeCtld::ContainerState do
  it 'preserves independent configuration and runtime states' do
    attrs = {
      id: '101',
      config_state: 'error',
      config_state_error: {
        source: 'lxc_config',
        message: 'invalid configuration'
      },
      runtime_state: 'running',
      runtime_state_error: nil
    }

    raw = NodeCtld::OsCtlContainer.new(attrs)
    typed = NodeCtld::Ct.new(attrs)

    expect(raw.config_state).to eq('error')
    expect(raw.runtime_state).to eq('running')
    expect(raw.config_state_error).to include(source: 'lxc_config')
    expect(typed.config_state).to eq(:error)
    expect(typed.runtime_state).to eq(:running)
    expect(typed.config_state_error).to include(source: 'lxc_config')
  end

  it 'normalizes ordinary legacy runtime states' do
    state = described_class.normalize(id: '101', state: 'running')

    expect(state).to include(
      config_state: 'ready',
      config_state_error: nil,
      runtime_state: 'running',
      runtime_state_error: nil
    )
    expect(state).not_to have_key(:state)
  end

  it 'normalizes legacy staged and error states without inventing runtime state' do
    staged = described_class.normalize(id: '101', state: 'staged')
    error = described_class.normalize(id: '102', state: 'error')

    expect(staged).to include(config_state: 'staged', runtime_state: 'unknown')
    expect(error).to include(
      config_state: 'error',
      runtime_state: 'unknown',
      config_state_error: include(
        source: 'legacy_state',
        message: include('undifferentiated error state')
      )
    )
  end
end
