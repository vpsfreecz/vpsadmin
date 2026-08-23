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

  it 'fails when nodectld cannot be paused' do
    allow(NodeCtld::RemoteClient).to receive(:send)
      .with(NodeCtld::RemoteControl::SOCKET, :pause)
      .and_raise(Errno::ENOENT)

    expect do
      described_class.pre_stop({})
    end.to raise_error(RuntimeError, /Failed to pause nodectld: Errno::ENOENT/)
  end

  it 'fails when nodectld rejects the pause request' do
    allow(NodeCtld::RemoteClient).to receive(:send)
      .with(NodeCtld::RemoteControl::SOCKET, :pause)
      .and_return(status: :failed, error: 'unsupported')

    expect do
      described_class.pre_stop({})
    end.to raise_error(RuntimeError, /rejected the pause request: "unsupported"/)
  end

  it 'sends a synchronous daemon resume request' do
    allow(NodeCtld::RemoteClient).to receive(:send)
      .with(NodeCtld::RemoteControl::SOCKET, :resume)
      .and_return(status: :ok)

    described_class.post_resume({})

    expect(NodeCtld::RemoteClient).to have_received(:send)
      .with(NodeCtld::RemoteControl::SOCKET, :resume)
  end

  it 'fails when nodectld cannot be resumed' do
    allow(NodeCtld::RemoteClient).to receive(:send)
      .with(NodeCtld::RemoteControl::SOCKET, :resume)
      .and_raise(Errno::ENOENT)

    expect do
      described_class.post_resume({})
    end.to raise_error(RuntimeError, /Failed to resume nodectld: Errno::ENOENT/)
  end

  it 'fails when nodectld rejects the resume request' do
    allow(NodeCtld::RemoteClient).to receive(:send)
      .with(NodeCtld::RemoteControl::SOCKET, :resume)
      .and_return(status: :failed, error: 'paused')

    expect do
      described_class.post_resume({})
    end.to raise_error(RuntimeError, /rejected the resume request: "paused"/)
  end
end
