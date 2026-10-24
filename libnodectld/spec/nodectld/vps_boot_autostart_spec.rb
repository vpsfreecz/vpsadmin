# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/vps_boot_autostart'
require 'nodectld/exporter'
require 'prometheus/client/formats/text'

RSpec.describe NodeCtld::VpsBootAutostart do
  let(:directory) { Dir.mktmpdir('boot-autostart-spec-') }
  let(:rpc) { instance_spy(NodeCtld::RpcClient) }
  let(:ledger) { NodeCtld::VpsBootAutostartLedger.new(path:, marker:, boot_id:) }
  let(:monitor) { described_class.new(ledger_factory: -> { ledger }, clock:) }
  let(:boottime) { [20.0] }

  def path
    File.join(directory, 'ledger.json')
  end

  def marker
    File.join(directory, 'marker')
  end

  def boot_id
    'current-boot'
  end

  def clock
    -> { boottime.fetch(0) }
  end

  def write_enrolling
    File.write(path, JSON.generate(
                       schema_version: 1, boot_id:, phase: 'enrolling',
                       capture_deadline_boottime_seconds: 300, failure_reason: nil,
                       captured_at_boottime_seconds: nil, obligations: []
                     ))
  end

  def inventory(*ids)
    { 'schema_version' => 1, 'vpses' => ids.map { |id| { 'id' => id, 'pool_fs' => 'tank/vps' } } }
  end

  def history(*ids)
    {
      'schema_version' => 1, 'boot_id' => boot_id, 'available' => true, 'reason' => nil,
      'entries' => ids.map { |id| { 'pool' => 'tank', 'id' => id.to_s, 'first_running_boottime_seconds' => 10 } }
    }
  end

  def reconciliation(*rows)
    { 'schema_version' => 1, 'vpses' => rows }
  end

  def expected(id, **changes)
    { 'id' => id, 'disposition' => 'retain', 'reason' => 'expected', 'pool_fs' => 'tank/vps' }.merge(changes.transform_keys(&:to_s))
  end

  def capture(*ids)
    allow(rpc).to receive(:list_vps_boot_autostart).and_return(inventory(*ids))
    monitor.update
    allow(monitor).to receive_messages(fetch_history: history, diagnostic_containers: {})
  end

  def render_boot_metrics
    registry = Prometheus::Client::Registry.new
    exporter = NodeCtld::Exporter.new(Struct.new(:vps_boot_autostart).new(monitor))
    metrics = exporter.send(:setup_metrics, registry)
    exporter.send(:collect_vps_boot_autostart_metrics, metrics)
    Prometheus::Client::Formats::Text.marshal(registry)
  end

  def block_once(entered, release)
    held = false
    lambda do
      unless held
        held = true
        entered << true
        release.pop
      end
    end
  end

  def block_capture(stage, barrier)
    case stage
    when :validation
      allow(ledger).to receive(:inventory).and_wrap_original do |original, *args|
        barrier.call
        original.call(*args)
      end
    when :fsync, :timeout_write
      allow(File).to receive(:open).and_wrap_original do |original, *args, &block|
        original.call(*args) do |file|
          if args.first.start_with?("#{path}.")
            allow(file).to receive(:fsync).and_wrap_original do |sync|
              barrier.call
              sync.call
            end
          end
          block.call(file)
        end
      end
    when :rename
      allow(File).to receive(:rename).and_wrap_original do |original, *args|
        barrier.call if args.last == path
        original.call(*args)
      end
    when :cleanup
      allow(ledger).to receive(:cleanup_temporary).and_wrap_original do |original, *args|
        barrier.call
        original.call(*args)
      end
    end
  end

  def pause_real_method(method, statement, thread, entered, release)
    source, first = monitor.method(method).source_location
    lines = File.readlines(source)
    last = (first...lines.length).find { |index| lines[index].start_with?('    def ') } || lines.length
    target = (first...last).find { |index| lines[index].strip == statement }
    raise "Missing real #{method} boundary" unless target

    trace = TracePoint.new(:line) do |event|
      next unless event.path == source && event.lineno == target + 1 && event.self.equal?(monitor)

      trace.disable
      entered << true
      release.pop
    end
    trace.enable(target_thread: thread)
    trace
  end

  before do
    boottime[0] = 20.0
    write_enrolling
    allow(NodeCtld::RpcClient).to receive(:new).and_return(rpc)
  end

  after { FileUtils.remove_entry(directory) }

  it 'constructs and scrapes memory-only state without loading the ledger or opening RPC' do
    allow(NodeCtld::VpsBootAutostartLedger).to receive(:new).and_call_original
    allow(File).to receive(:read).and_call_original
    allow(File).to receive(:open).and_call_original
    unloaded = described_class.new(clock:)
    expect(unloaded.snapshot.state).to eq('unavailable')
    expect(unloaded.snapshot.reason).to eq('state_loading')
    expect(unloaded.snapshot.success).to be(false)
    expect(unloaded.snapshot.last_success_at).to eq(0)
    expect(unloaded.snapshot.expected).to be_empty
    expect(unloaded.snapshot.unsatisfied).to be_empty
    expect(unloaded.snapshot.unsatisfied_counts).to be_empty
    expect(unloaded.snapshot).to be_frozen
    allow(monitor).to receive(:snapshot).and_return(unloaded.snapshot)
    expect(render_boot_metrics).to include('state="unavailable",reason="state_loading"')
    expect(render_boot_metrics).not_to include('nodectld_vps_boot_autostart_unsatisfied{')
    expect(NodeCtld::RpcClient).not_to have_received(:new)
    expect(NodeCtld::VpsBootAutostartLedger).not_to have_received(:new)
    expect(File).not_to have_received(:read)
    expect(File).not_to have_received(:open)
  end

  %w[active enrolling].each do |phase|
    it "keeps unknown loading separate from expiry and resumes late #{phase} state correctly" do
      ledger.capture(inventory(101), now: 20) if phase == 'active'
      entered = Queue.new
      release = Queue.new
      loading = described_class.new(ledger_factory: lambda {
        entered << true
        release.pop
        NodeCtld::VpsBootAutostartLedger.new(path:, marker:, boot_id:)
      }, clock:)
      allow(loading).to receive_messages(fetch_history: history(101), diagnostic_containers: {})
      worker = Thread.new { loading.update }
      expect(entered.pop(timeout: 2)).to be(true)
      boottime[0] = 86_400
      3.times do
        expect(loading.snapshot.reason).to eq('state_loading')
        expect(loading.snapshot.success).to be(false)
        expect(loading.snapshot.unsatisfied).to be_empty
      end
      expect(worker.alive?).to be(true)
      expect(NodeCtld::RpcClient).not_to have_received(:new)
      release << true
      expect(worker.join(2)).not_to be_nil
      if phase == 'active'
        expect(loading.snapshot.state).to eq('active')
        expect(loading.snapshot.success).to be(true)
        expect(loading.snapshot.expected).to eq('tank' => 1)
      else
        expect(loading.snapshot.reason).to eq('enrollment_timeout')
        expect(loading.snapshot.unsatisfied).to be_empty
      end
      expect(NodeCtld::RpcClient).not_to have_received(:new)
    ensure
      release << true if worker&.alive?
      worker&.join(2)
    end
  end

  it 'keeps a ledger initialization exception terminal without retrying or touching nil state' do
    factory = instance_double(Proc)
    allow(factory).to receive(:call).and_raise(IOError, 'read failed')
    failed = described_class.new(ledger_factory: factory, clock:)
    expect(failed.snapshot.reason).to eq('state_loading')
    3.times do
      failed.update
      expect(failed.snapshot.reason).to eq('state_invalid')
      expect(failed.snapshot.success).to be(false)
      expect(failed.snapshot.last_success_at).to eq(0)
      expect(failed.snapshot.expected).to be_empty
    end
    expect(factory).to have_received(:call).once
    expect(NodeCtld::RpcClient).not_to have_received(:new)
    expect(JSON.parse(File.read(path)).fetch('phase')).to eq('enrolling')
  end

  it 'captures the first complete inventory asynchronously and preserves it on restart' do
    expect(monitor.snapshot.reason).to eq('state_loading')
    capture(101, 102)
    expect(monitor.snapshot.state).to eq('active')
    expect(monitor.snapshot.state).to be_frozen
    expect(monitor.snapshot.reason).to be_frozen
    expect(File.stat(path).mode & 0o777).to eq(0o600)
    restarted = described_class.new(
      ledger_factory: -> { NodeCtld::VpsBootAutostartLedger.new(path:, marker:, boot_id:) }, clock:
    )
    expect(restarted.snapshot.reason).to eq('state_loading')
    allow(restarted).to receive_messages(fetch_history: history(101, 102), diagnostic_containers: {})
    restarted.update
    expect(restarted.snapshot.success).to be(true)
    expect(ledger.obligations.map { |row| row['id'] }).to eq([101, 102])
    expect(rpc).to have_received(:list_vps_boot_autostart).once
  end

  %i[setup request close].each do |stage|
    it "expires known enrollment while ordinary RPC #{stage} remains blocked" do
      entered = Queue.new
      release = Queue.new
      barrier = block_once(entered, release)
      allow(rpc).to receive(:list_vps_boot_autostart).and_return(inventory(101))
      case stage
      when :setup
        allow(NodeCtld::RpcClient).to receive(:new) do
          barrier.call
          rpc
        end
      when :request
        allow(rpc).to receive(:list_vps_boot_autostart) do
          barrier.call
          inventory(101)
        end
      when :close
        allow(rpc).to receive(:close) { barrier.call }
      end
      worker = Thread.new { monitor.update }
      expect(entered.pop(timeout: 2)).to be(true)
      expect(monitor.snapshot.state).to eq('enrolling')
      boottime[0] = 300
      probe = Thread.new { [monitor.snapshot, render_boot_metrics] }
      expect(probe.join(1)).not_to be_nil
      current, output = probe.value
      expect(current.reason).to eq('enrollment_timeout')
      expect(current.success).to be(false)
      expect(output).not_to include('nodectld_vps_boot_autostart_unsatisfied{')
      expect(worker.alive?).to be(true)
      expect(ledger.obligations).to be_empty
      release << true
      expect(worker.join(2)).not_to be_nil
      expect(ledger.phase).to eq('unavailable')
      expect(ledger.obligations).to be_empty
      expect(monitor.snapshot.reason).to eq('enrollment_timeout')
    ensure
      release << true if worker&.alive?
      worker&.join(2)
      probe&.join(2)
    end
  end

  it 'closes the ordinary RPC client before validating or persisting inventory' do
    allow(rpc).to receive(:list_vps_boot_autostart).and_return(inventory(101))
    allow(ledger).to receive(:capture).and_call_original
    allow(ledger).to receive(:inventory).and_wrap_original do |original, response|
      expect(rpc).to have_received(:close).once
      original.call(response)
    end
    monitor.update
    expect(ledger.phase).to eq('active')
    expect(ledger).to have_received(:capture).once
    expect(ledger).to have_received(:inventory).once
  end

  it 'rejects inventory when ordinary close finishes after the host cutoff' do
    boottime[0] = 299.0
    allow(rpc).to receive(:list_vps_boot_autostart).and_return(inventory(101))
    allow(rpc).to receive(:close) { boottime[0] = 301.0 }
    monitor.update
    expect(ledger.phase).to eq('unavailable')
    expect(ledger.obligations).to be_empty
    expect(monitor.snapshot.reason).to eq('enrollment_timeout')
  end

  %i[validation fsync rename cleanup timeout_write].each do |stage|
    it "exports unavailable while worker #{stage} remains blocked" do
      boottime[0] = stage == :timeout_write ? 300.0 : 299.0
      entered = Queue.new
      release = Queue.new
      barrier = block_once(entered, release)
      allow(rpc).to receive(:list_vps_boot_autostart).and_return(inventory(101))
      block_capture(stage, barrier)
      worker = Thread.new { monitor.update }
      expect(entered.pop(timeout: 2)).to be(true)
      if stage != :timeout_write
        early_probe = Thread.new { monitor.snapshot.state }
        expect(early_probe.join(1)).not_to be_nil
        expect(early_probe.value).to eq('enrolling')
      end
      boottime[0] = 300.0
      probe = Thread.new { [monitor.snapshot, render_boot_metrics] }
      expect(probe.join(1)).not_to be_nil
      current, output = probe.value
      expect(current.state).to eq('unavailable')
      expect(current.reason).to eq('enrollment_timeout')
      expect(current).to be_frozen
      expect(output).to include('nodectld_vps_boot_autostart_state{state="unavailable",reason="enrollment_timeout"} 1.0')
      expect(output).to include('nodectld_vps_boot_autostart_check_success 0.0')
      expect(output).not_to include('nodectld_vps_boot_autostart_unsatisfied{')
      # It is the still-held barrier, not worker completion, that proves the bound.
      expect(worker.alive?).to be(true)
      release << true
      expect(worker.join(2)).not_to be_nil
      expect(monitor.snapshot.state).to eq('unavailable')
      expect(ledger.phase).to eq('unavailable')
      expect(ledger.obligations).to be_empty
      reloaded = NodeCtld::VpsBootAutostartLedger.new(path:, marker:, boot_id:)
      expect(reloaded.phase).to eq('unavailable')
      expect(reloaded.obligations).to be_empty
      boottime[0] = 299.0
      monitor.update
      expect(monitor.snapshot.state).to eq('unavailable')
    ensure
      release << true if worker&.alive?
      worker&.join(2)
      probe&.join(2)
      early_probe&.join(2)
    end
  end

  %i[snapshot delayed_snapshot].each do |observer|
    it "keeps observed expiry authoritative across stale active publication with #{observer}" do
      boottime[0] = 299.5
      started = Queue.new
      entered = Queue.new
      release = Queue.new
      reader_started = Queue.new
      reader_entered = Queue.new
      reader_release = Queue.new
      allow(rpc).to receive(:list_vps_boot_autostart).and_return(inventory(101))
      allow(monitor).to receive_messages(fetch_history: history(101), diagnostic_containers: {})
      worker = Thread.new do
        started.pop
        monitor.update
      end
      trace = pause_real_method(:enroll, '@enrolling = false', worker, entered, release)
      started << true
      expect(entered.pop(timeout: 2)).to be(true)
      expect(ledger.phase).to eq('active')
      boottime[0] = 300.0
      if observer == :delayed_snapshot
        method = :snapshot
        statement = 'if publication.enrolling && now >= VpsBootAutostartLedger::DEADLINE'
        reader = Thread.new do
          reader_started.pop
          monitor.public_send(method)
        end
        reader_trace = pause_real_method(method, statement, reader, reader_entered, reader_release)
        reader_started << true
        expect(reader_entered.pop(timeout: 2)).to be(true)
        # The reader has captured pending. Let the real worker publish active
        # before that reader's terminal rejection store.
        release << true
        expect(worker.join(2)).not_to be_nil
        reader_release << true
        expect(reader.join(2)).not_to be_nil
      else
        reader = Thread.new { monitor.snapshot }
        expect(reader.join(1)).not_to be_nil
        expect(worker.alive?).to be(true)
        release << true
        expect(worker.join(2)).not_to be_nil
      end
      3.times do
        expect(monitor.snapshot.state).to eq('unavailable')
        expect(monitor.snapshot.reason).to eq('enrollment_timeout')
      end
      expect(render_boot_metrics).to include('nodectld_vps_boot_autostart_check_success 0.0')
      expect(render_boot_metrics).not_to include('nodectld_vps_boot_autostart_unsatisfied{')
      monitor.update
      expect(monitor).not_to have_received(:fetch_history)
      expect(monitor).not_to have_received(:diagnostic_containers)
      expect(rpc).not_to have_received(:reconcile_vps_boot_autostart)
      expect(ledger.phase).to eq('unavailable')
      reloaded = NodeCtld::VpsBootAutostartLedger.new(path:, marker:, boot_id:)
      expect(reloaded.phase).to eq('unavailable')
      expect(reloaded.obligations).to be_empty
      boottime[0] = 299.0
      monitor.update
      expect(monitor.snapshot.state).to eq('unavailable')
      expect(monitor).not_to have_received(:fetch_history)
    ensure
      trace&.disable
      reader_trace&.disable
      started << true if worker&.alive?
      release << true if worker&.alive?
      reader_started << true if reader&.alive?
      reader_release << true if reader&.alive?
      worker&.join(2)
      reader&.join(2)
    end
  end

  it 'keeps a timely accepted cohort healthy through deadline observation and later uptime' do
    boottime[0] = 299.5
    capture(101)
    allow(rpc).to receive(:reconcile_vps_boot_autostart).and_return(reconciliation(expected(101)))
    [300.0, 86_400.0].each do |uptime|
      boottime[0] = uptime
      expect(monitor.snapshot.state).to eq('active')
      monitor.update
      expect(monitor.snapshot.state).to eq('active')
      expect(monitor.snapshot.success).to be(true)
      expect(monitor.snapshot.unsatisfied.map(&:vps_id)).to eq(['101'])
    end
  end

  it 'reads only published metadata when known enrollment expires' do
    allow(rpc).to receive(:list_vps_boot_autostart).and_raise(NodeCtld::RpcClient::Error, 'offline')
    monitor.update
    expect(monitor.snapshot.state).to eq('enrolling')
    boottime[0] = 300.0
    allow(ledger).to receive(:phase).and_raise('snapshot touched ledger')
    allow(ledger).to receive(:enrollment_failed).and_raise('snapshot wrote ledger')
    3.times { expect(monitor.snapshot.reason).to eq('enrollment_timeout') }
    expect(ledger).not_to have_received(:enrollment_failed)
  end

  it 'never requests inventory when first started late' do
    boottime[0] = 900
    monitor.update
    expect(rpc).not_to have_received(:list_vps_boot_autostart)
    expect(monitor.snapshot.reason).to eq('enrollment_timeout')
  end

  it 'retries malformed inventory without resetting the boot deadline' do
    allow(rpc).to receive(:list_vps_boot_autostart).and_return(inventory(101, 101))
    monitor.update
    expect(monitor.snapshot.state).to eq('enrolling')
    boottime[0] = 300
    expect(monitor.snapshot.reason).to eq('inventory_invalid')
  end

  it 'distinguishes a live upgrade from lost state during a feature boot' do
    File.unlink(path)
    monitor.update
    expect(monitor.snapshot.state).to eq('awaiting_reboot')
    File.write(marker, "1\n")
    lost = NodeCtld::VpsBootAutostartLedger.new(path:, marker:, boot_id:)
    expect(lost.failure_reason).to eq('state_missing')
    expect(File.exist?(path)).to be(false)
  end

  it 'does not recreate corrupted or foreign boot state' do
    File.write(path, '{}')
    monitor.update
    expect(monitor.snapshot.reason).to eq('state_invalid')
    write_enrolling
    foreign = NodeCtld::VpsBootAutostartLedger.new(path:, marker:, boot_id: 'other-boot')
    expect(foreign.failure_reason).to eq('boot_id_mismatch')
  end

  %i[setup request close].each do |stage|
    it "persists fulfilment before retirement #{stage} can hang and leaves freshness unchanged" do
      capture(101, 102)
      allow(rpc).to receive(:reconcile_vps_boot_autostart).and_return(reconciliation(expected(101), expected(102)))
      allow(Time).to receive(:now).and_return(Time.at(1000))
      monitor.update
      expect(monitor.snapshot.last_success_at).to eq(1000)
      entered = Queue.new
      release = Queue.new
      barrier = block_once(entered, release)
      allow(monitor).to receive(:fetch_history).and_return(history(101))
      allow(rpc).to receive(:reconcile_vps_boot_autostart).with([102]).and_return(reconciliation(expected(102)))
      case stage
      when :setup
        allow(NodeCtld::RpcClient).to receive(:new) do
          barrier.call
          rpc
        end
      when :request
        allow(rpc).to receive(:reconcile_vps_boot_autostart).with([102]) do
          barrier.call
          reconciliation(expected(102))
        end
      when :close
        allow(rpc).to receive(:close) { barrier.call }
      end
      worker = Thread.new { monitor.update }
      expect(entered.pop(timeout: 2)).to be(true)
      persisted = NodeCtld::VpsBootAutostartLedger.new(path:, marker:, boot_id:)
      expect(persisted.obligations.map { |row| row['state'] }).to eq(%w[fulfilled pending])
      boottime[0] = 86_400
      allow(Time).to receive(:now).and_return(Time.at(2000))
      probe = Thread.new { monitor.snapshot }
      expect(probe.join(1)).not_to be_nil
      expect(probe.value.last_success_at).to eq(1000)
      expect(worker.alive?).to be(true)
      release << true
      expect(worker.join(2)).not_to be_nil
      expect(monitor.snapshot.last_success_at).to eq(2000)
      expect(ledger.obligations.first['state']).to eq('fulfilled')
    ensure
      release << true if worker&.alive?
      worker&.join(2)
      probe&.join(2)
    end
  end

  it 'closes each retirement client before response validation and persists no failed-close retirement' do
    capture(101)
    allow(rpc).to receive(:reconcile_vps_boot_autostart).and_return(reconciliation(
                                                                      expected(101, disposition: 'retire', reason: 'deleted', pool_fs: nil)
                                                                    ))
    allow(rpc).to receive(:close).and_raise(IOError, 'close failed')
    allow(monitor).to receive(:validate_reconciliation).and_call_original
    monitor.update
    expect(ledger.pending.map { |row| row['id'] }).to eq([101])
    expect(monitor.snapshot.reason).to eq('rpc_failed')
    expect(monitor.snapshot.last_success_at).to eq(0)
    expect(monitor).not_to have_received(:validate_reconciliation)
  end

  it 'uses one ordinary client lifecycle for each sorted pending batch' do
    capture(*(1..1001).to_a)
    first = (1..1000).to_a
    allow(rpc).to receive(:reconcile_vps_boot_autostart).with(first).and_return(reconciliation(*first.map { |id| expected(id) }))
    allow(rpc).to receive(:reconcile_vps_boot_autostart).with([1001]).and_return(reconciliation(expected(1001)))
    monitor.update
    expect(monitor.snapshot.success).to be(true)
    expect(NodeCtld::RpcClient).to have_received(:new).exactly(3).times
    expect(rpc).to have_received(:close).exactly(3).times
    expect(rpc).to have_received(:reconcile_vps_boot_autostart).with(first).once
    expect(rpc).to have_received(:reconcile_vps_boot_autostart).with([1001]).once
  end

  [
    [NodeCtld::RpcClient::Timeout, 'unsupported inventory_invalid', 'rpc_failed'],
    [NodeCtld::RpcClient::Error, 'Unknown command', 'rpc_unsupported'],
    [NodeCtld::RpcClient::Error, 'unsupported', 'rpc_unsupported'],
    [NodeCtld::RpcClient::Error, 'not allowed', 'rpc_unsupported'],
    [NodeCtld::RpcClient::Error, 'invalid method', 'rpc_unsupported'],
    [NodeCtld::RpcClient::Error, 'Command list_vps_boot_autostart not found', 'rpc_unsupported'],
    [NodeCtld::RpcClient::Error, 'inventory_invalid', 'inventory_invalid'],
    [NodeCtld::RpcClient::Error, 'Server error: inventory_invalid', 'inventory_invalid'],
    [NodeCtld::RpcClient::Error, 'inventory_invalid extra', 'rpc_failed'],
    [NodeCtld::RpcClient::Error, 'offline', 'rpc_failed'],
    [JSON::ParserError, 'bad json', 'response_invalid'],
    [IOError, 'setup/close failed', 'rpc_failed']
  ].each do |klass, message, reason|
    it "maps #{klass}: #{message.inspect} to #{reason} without exposing actionable rows" do
      capture(101)
      allow(rpc).to receive(:reconcile_vps_boot_autostart).and_raise(klass, message)
      monitor.update
      expect(monitor.snapshot.reason).to eq(reason)
      expect(monitor.snapshot.success).to be(false)
      expect(monitor.snapshot.last_success_at).to eq(0)
      expect(monitor.snapshot.unsatisfied).to be_empty
      expect(ledger.pending.length).to eq(1)
    end
  end

  it 'fulfils successful history even while API reconciliation fails' do
    capture(101, 102)
    allow(monitor).to receive(:fetch_history).and_return(history(101))
    allow(rpc).to receive(:reconcile_vps_boot_autostart).with([102])
                                                        .and_raise(NodeCtld::RpcClient::Error, 'rpc_failed')
    monitor.update
    expect(ledger.obligations.map { |row| row['state'] }).to eq(%w[fulfilled pending])
    expect(monitor.snapshot.success).to be(false)
    expect(monitor.snapshot.unsatisfied).to be_empty
    reloaded = NodeCtld::VpsBootAutostartLedger.new(path:, marker:, boot_id:)
    expect(reloaded.obligations.first['state']).to eq('fulfilled')
  end

  it 'keeps terminal obligations and the fixed cohort across restart and later observations' do
    capture(101, 102, 103)
    allow(monitor).to receive(:fetch_history).and_return(history(101))
    allow(rpc).to receive(:reconcile_vps_boot_autostart).with([102, 103]).and_return(
      reconciliation(expected(102, disposition: 'retire', reason: 'autostart_disabled', pool_fs: nil), expected(103))
    )
    monitor.update
    expect(ledger.obligations.map { |row| row['state'] }).to eq(%w[fulfilled retired pending])
    terminal_rows = ledger.obligations.first(2)
    allow(rpc).to receive(:list_vps_boot_autostart).and_return(inventory(101, 102, 103, 104))

    [
      [3600, { %w[tank 101] => 'stopped', %w[tank 102] => 'stopped', %w[tank 103] => 'stopped' }, 'not_running'],
      [7200, {}, 'missing'],
      [86_400, { %w[archive 101] => 'stopped', %w[archive 102] => 'running',
                 %w[archive 103] => 'stopped', %w[tank 104] => 'running' }, 'missing']
    ].each do |uptime, diagnostics, reason|
      boottime[0] = uptime
      reloaded = NodeCtld::VpsBootAutostartLedger.new(path:, marker:, boot_id:)
      reloaded_rpc = instance_spy(NodeCtld::RpcClient)
      allow(reloaded_rpc).to receive(:reconcile_vps_boot_autostart).with([103])
                                                                   .and_return(reconciliation(expected(103)))
      allow(NodeCtld::RpcClient).to receive(:new).and_return(reloaded_rpc)
      resumed = described_class.new(ledger_factory: -> { reloaded }, clock:)
      # Full-boot summaries survive recent timeline eviction. Later identity104
      # and renewed running evidence for retired102 do not alter the cohort.
      allow(resumed).to receive_messages(fetch_history: history(101, 102, 104), diagnostic_containers: diagnostics)
      resumed.update
      expect(resumed.snapshot.success).to be(true)
      expect(resumed.snapshot.expected).to eq('tank' => 3)
      expect(resumed.snapshot.unsatisfied.map { |row| [row.pool, row.vps_id, row.reason] })
        .to eq([['tank', '103', reason]])
      expect(reloaded.obligations.map { |row| row['id'] }).to eq([101, 102, 103])
      expect(reloaded.obligations.map { |row| row['state'] }).to eq(%w[fulfilled retired pending])
      expect(reloaded.obligations.first(2)).to eq(terminal_rows)
      expect(reloaded_rpc).not_to have_received(:list_vps_boot_autostart)
      expect(reloaded_rpc).to have_received(:reconcile_vps_boot_autostart).with([103]).once
    end
    expect(rpc).to have_received(:list_vps_boot_autostart).once
  end

  JSON.parse(File.read(File.expand_path('../../../tests/fixtures/boot-autostart-pool-filesystems.json', __dir__))).each do |fixture|
    it "matches the API filesystem contract for #{fixture.fetch('filesystem').inspect}" do
      pool_fs = fixture.fetch('filesystem')
      response = inventory(101)
      response.fetch('vpses').first['pool_fs'] = pool_fs
      allow(rpc).to receive(:list_vps_boot_autostart).and_return(response)
      monitor.update
      expect(ledger.pool_fs?(pool_fs)).to be(fixture.fetch('valid'))
      if fixture.fetch('valid')
        expect(ledger.phase).to eq('active')
        reloaded = NodeCtld::VpsBootAutostartLedger.new(path:, marker:, boot_id:)
        expect(reloaded.phase).to eq('active')
        expect(reloaded.obligations.first['pool_fs']).to eq(pool_fs)
        allow(monitor).to receive_messages(fetch_history: history, diagnostic_containers: {})
        allow(rpc).to receive(:reconcile_vps_boot_autostart).and_return(reconciliation(expected(101, pool_fs:)))
        monitor.update
        expect(monitor.snapshot.success).to be(true)
        expect(ledger.pending.length).to eq(1)
      else
        expect(ledger.phase).to eq('enrolling')
        expect(monitor.snapshot.success).to be(false)
      end
    end
  end

  it 'accepts API child dataset names at enrollment and pending reconciliation' do
    response = inventory(101)
    response.fetch('vpses').first['pool_fs'] = 'tank/_vps'
    allow(rpc).to receive_messages(
      list_vps_boot_autostart: response,
      reconcile_vps_boot_autostart: reconciliation(expected(101, pool_fs: 'tank/-vps'))
    )
    monitor.update
    expect(ledger.phase).to eq('active')
    expect(ledger.obligations.first['pool_fs']).to eq('tank/_vps')
    allow(monitor).to receive_messages(fetch_history: history, diagnostic_containers: {})
    monitor.update
    expect(monitor.snapshot.success).to be(true)
    expect(ledger.pending.length).to eq(1)
  end

  it 'rejects empty, dot and parent dataset components' do
    %w[tank//vps tank/./vps tank/../vps tank/ tank/vps/..].each do |pool_fs|
      response = inventory(101)
      response.fetch('vpses').first['pool_fs'] = pool_fs
      expect { ledger.inventory(response) }.to raise_error(NodeCtld::VpsBootAutostartLedger::Invalid)
    end
  end

  it 'retains locked and transitional entries, and retires a changed pool' do
    capture(101, 102, 103)
    allow(rpc).to receive(:reconcile_vps_boot_autostart).and_return(reconciliation(
                                                                      expected(101, reason: 'resource_locked', pool_fs: nil),
                                                                      expected(102, reason: 'transitional', pool_fs: nil),
                                                                      expected(103, pool_fs: 'archive/vps')
                                                                    ))
    monitor.update
    expect(ledger.obligations.map { |row| row['state'] }).to eq(%w[pending pending retired])
    expect(ledger.obligations.last['reason']).to eq('pool_changed')
  end

  it 'rejects incomplete retirement evidence and preserves obligations' do
    capture(101, 102)
    allow(rpc).to receive(:reconcile_vps_boot_autostart).and_return(reconciliation(expected(101)))
    monitor.update
    expect(monitor.snapshot.reason).to eq('response_invalid')
    expect(ledger.pending.length).to eq(2)
  end

  it 'fulfils numeric VPS history alongside unrelated valid generic container IDs' do
    capture(101)
    allow(monitor).to receive(:fetch_history).and_return(history(101, '_ct', '-ct', 'A' * 100))
    monitor.update
    expect(monitor.snapshot.success).to be(true)
    expect(ledger.obligations.first['state']).to eq('fulfilled')
    expect(monitor.snapshot.unsatisfied).to be_empty
    expect(rpc).not_to have_received(:reconcile_vps_boot_autostart)
  end

  it 'rejects malformed generic history IDs without fulfilling any obligation' do
    capture(101)
    ['', 'a' * 101, "ct\n", 'ct.name', 'ct:name', 'ct/name'].each do |id|
      allow(monitor).to receive(:fetch_history).and_return(history(101, id))
      monitor.update
      expect(monitor.snapshot.reason).to eq('response_invalid')
      expect(ledger.pending.length).to eq(1)
    end
  end

  it 'rejects duplicate, foreign-boot and unavailable history without claiming an empty success' do
    capture(101)
    [history(101, 101), history(101).merge('boot_id' => 'foreign'),
     history.merge('available' => false, 'reason' => 'state_missing')].each do |response|
      allow(monitor).to receive(:fetch_history).and_return(response)
      monitor.update
      expect(monitor.snapshot.success).to be(false)
      expect(ledger.pending.length).to eq(1)
    end
  end

  it 'checks provider health for an empty cohort without reconcile RPC' do
    capture
    monitor.update
    expect(rpc).not_to have_received(:reconcile_vps_boot_autostart)
    expect(monitor.snapshot.success).to be(true)
    expect(monitor.snapshot.expected).to be_empty
    expect(monitor).to have_received(:fetch_history)
  end

  it 'queries the permanent running projection and fulfils a stopped VPS from its summary' do
    capture(101, 102)
    allow(monitor).to receive(:fetch_history).and_call_original
    allow(monitor).to receive(:diagnostic_containers).and_call_original
    allow(monitor).to receive(:syscmd).with('osctl -j ct state-history --ever-running', {})
                                      .and_return(Struct.new(:output).new(JSON.generate(history(101))))
    allow(monitor).to receive(:syscmd).with('osctl -j ct ls', {})
                                      .and_return(Struct.new(:output).new(JSON.generate([
                                                                                          { pool: 'tank', id: '101', state: 'stopped' },
                                                                                          { pool: 'tank', id: '102', state: 'stopped' }
                                                                                        ])))
    allow(rpc).to receive(:reconcile_vps_boot_autostart).with([102])
                                                        .and_return(reconciliation(expected(102)))
    monitor.update
    expect(monitor.snapshot.success).to be(true)
    expect(ledger.obligations.map { |row| row['state'] }).to eq(%w[fulfilled pending])
    expect(monitor.snapshot.unsatisfied.map(&:vps_id)).to eq(['102'])
    expect(monitor.snapshot.unsatisfied.first.reason).to eq('not_running')
    expect(monitor).to have_received(:syscmd).with('osctl -j ct state-history --ever-running', {})
  end

  it 'withholds actionable metrics and preserves freshness when a later check fails' do
    capture(101)
    allow(rpc).to receive(:reconcile_vps_boot_autostart).and_return(reconciliation(expected(101)))
    monitor.update
    successful = monitor.snapshot
    allow(monitor).to receive(:diagnostic_containers).and_raise(described_class::Failure, 'osctld_unavailable')
    monitor.update
    expect(monitor.snapshot.last_success_at).to eq(successful.last_success_at)
    expect(monitor.snapshot.expected).to be_empty
    expect(monitor.snapshot.unsatisfied).to be_empty
    expect(ledger.pending.length).to eq(1)
  end

  it 'does not publish a terminal transition when atomic persistence fails' do
    capture(101)
    allow(monitor).to receive(:fetch_history).and_return(history(101))
    allow(File).to receive(:rename).and_raise(Errno::EIO)
    monitor.update
    expect(monitor.snapshot.reason).to eq('persistence_failed')
    expect(ledger.pending.length).to eq(1)
  end

  it 'keeps a failed retirement unavailable across daemon restart even if intent changes back' do
    capture(101)
    allow(rpc).to receive(:reconcile_vps_boot_autostart).and_return(reconciliation(
                                                                      expected(101, disposition: 'retire', reason: 'autostart_disabled', pool_fs: nil)
                                                                    ))
    allow(File).to receive(:rename).and_call_original
    allow(File).to receive(:rename).with(anything, path).and_raise(Errno::EIO)
    monitor.update
    expect(monitor.snapshot.reason).to eq('persistence_failed')
    expect(File.exist?("#{path.delete_suffix('.json')}.failed.json")).to be(true)
    restarted = described_class.new(ledger_factory: -> { NodeCtld::VpsBootAutostartLedger.new(path:, marker:, boot_id:) }, clock:)
    allow(rpc).to receive(:reconcile_vps_boot_autostart).and_return(reconciliation(expected(101)))
    restarted.update
    expect(restarted.snapshot.reason).to eq('persistence_failed')
  end

  it 'does not recapture after failed capture leaves an older enrolling record' do
    original = File.read(path)
    allow(File).to receive(:rename).and_raise(Errno::EIO)
    capture(101)
    expect(monitor.snapshot.reason).to eq('persistence_failed')
    File.write(path, original)
    restarted = described_class.new(ledger_factory: -> { NodeCtld::VpsBootAutostartLedger.new(path:, marker:, boot_id:) }, clock:)
    restarted.update
    expect(restarted.snapshot.reason).to eq('persistence_failed')
    expect(rpc).to have_received(:list_vps_boot_autostart).once
  end

  it 'lets a sentinel override a restored valid ledger, including malformed failure evidence' do
    capture(101)
    File.write("#{path.delete_suffix('.json')}.failed.json", 'broken')
    restarted = NodeCtld::VpsBootAutostartLedger.new(path:, marker:, boot_id:)
    expect(restarted.failure_reason).to eq('persistence_failed')
    expect(restarted.obligations).to be_empty
  end
end
