# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/zfs_stream'

RSpec.describe NodeCtld::ZfsStream do
  let(:stream) { described_class.allocate }
  let(:read_end) { instance_double(IO, close: nil) }
  let(:write_end) { instance_double(IO, close: nil) }
  let(:stderr_pipe) { instance_double(IO, close: nil) }
  let(:ok_status) { instance_double(Process::Status, success?: true, exitstatus: 0, termsig: nil) }

  before do
    stream.instance_variable_set(:@progress, [])

    allow(IO).to receive(:pipe).and_return([read_end, write_end])
    allow(Process).to receive(:fork).and_return(101)
    allow(stream).to receive(:zfs_send).and_return([202, stderr_pipe])
    allow(stream).to receive(:monitor_progress)
    allow(stream).to receive(:notify_exec)
    allow(stream).to receive(:log)
  end

  it 'raises when the transport helper exits unsuccessfully' do
    failed_status = instance_double(Process::Status, success?: false, exitstatus: 1, termsig: nil)

    allow(Process).to receive(:wait2).with(202).and_return([202, ok_status])
    allow(Process).to receive(:wait2).with(101).and_return([101, failed_status])

    expect { stream.send(:pipe_cmd, ['/run/test/faulty-mbuffer', '-q', '-O', '127.0.0.1:39001']) }
      .to raise_error(OsCtl::Lib::Exceptions::SystemCommandFailed) do |error|
        expect(error.cmd).to include('/run/test/faulty-mbuffer')
        expect(error.rc).to eq(1)
      end
  end

  it 'returns when both pipeline processes succeed' do
    allow(Process).to receive(:wait2).with(202).and_return([202, ok_status])
    allow(Process).to receive(:wait2).with(101).and_return([101, ok_status])

    expect { stream.send(:pipe_cmd, ['mbuffer', '-q', '-O', '127.0.0.1:39001']) }.not_to raise_error
  end

  it 'passes transport helper options as separate argv elements' do
    allow(stream).to receive(:pipe_cmd)

    stream.send_to(
      '127.0.0.1',
      39_001,
      command: '/run/test/faulty-mbuffer',
      block_size: '1M',
      buffer_size: '256M',
      log_file: '/run/test/mbuffer.log',
      timeout: 5
    )

    expect(stream).to have_received(:pipe_cmd).with(
      [
        '/run/test/faulty-mbuffer',
        '-q',
        '-O', '127.0.0.1:39001',
        '-s', '1M',
        '-m', '256M',
        '-l', '/run/test/mbuffer.log',
        '-W', '5'
      ]
    )
  end
end
