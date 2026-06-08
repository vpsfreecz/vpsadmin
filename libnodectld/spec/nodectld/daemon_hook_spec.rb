# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/daemon_hook'

RSpec.describe NodeCtld::DaemonHook do
  it 'sends a synchronous daemon pause request' do
    allow(NodeCtld::RemoteClient).to receive(:send)
      .with(NodeCtld::RemoteControl::SOCKET, :pause)
      .and_return(status: :ok)

    described_class.pre_stop({})

    expect(NodeCtld::RemoteClient).to have_received(:send)
      .with(NodeCtld::RemoteControl::SOCKET, :pause)
  end

  it 'uses the configured pause timeout' do
    allow(NodeCtld::RemoteClient).to receive(:send)
      .with(NodeCtld::RemoteControl::SOCKET, :pause)
      .and_return(status: :ok)
    allow(Timeout).to receive(:timeout).and_call_original

    described_class.pre_stop(described_class::PRE_STOP_TIMEOUT => '2.5')

    expect(Timeout).to have_received(:timeout).with(2.5)
  end

  it 'warns and continues when nodectld is unavailable' do
    allow(NodeCtld::RemoteClient).to receive(:send)
      .with(NodeCtld::RemoteControl::SOCKET, :pause)
      .and_raise(Errno::ENOENT)

    expect do
      described_class.pre_stop({})
    end.to output(/Failed to pause nodectld: Errno::ENOENT/).to_stderr
  end

  it 'warns and continues when nodectld rejects the pause request' do
    allow(NodeCtld::RemoteClient).to receive(:send)
      .with(NodeCtld::RemoteControl::SOCKET, :pause)
      .and_return(status: :failed, error: 'unsupported')

    expect do
      described_class.pre_stop({})
    end.to output(/Failed to pause nodectld: "unsupported"/).to_stderr
  end
end
