# frozen_string_literal: true

require 'json'
require 'tmpdir'
require 'fileutils'
require 'timeout'
require 'rbconfig'
require_relative '../ci_environment'

RSpec.describe RequestExceptionDiagnostics do
  let(:env) { { 'REQUEST_METHOD' => 'POST', 'PATH_INFO' => '/private-sentinel', 'HTTP_AUTHORIZATION' => 'secret-sentinel' } }
  let(:error) { RuntimeError.new('secret-sentinel SQL private body') }
  let(:owner) { stub_const('SpecDiagnosticHooks', Class.new) }

  before do
    described_class.discard(RSpec.current_example)
    %i[exec_exception request_exception].each { |name| HaveAPI::Hooks.register_hook(owner, name) }
  end

  after do
    HaveAPI::Hooks.hooks.delete(owner)
    described_class.discard(RSpec.current_example)
  end

  def context_for(request_env)
    HaveAPI::Context.new(nil, request: Struct.new(:env).new(request_env))
  end

  def dispatch(name = :exec_exception, exception = error, request_env = env, **options, &block)
    HaveAPI::Hooks.connect_hook(owner, name, &block) if block
    HaveAPI::Hooks.call_for(owner, name, nil, args: [context_for(request_env), exception], **options)
  end

  def request(request_env = env, &block)
    described_class::App.new(block).call(request_env)
  end

  def packet
    described_class.take(RSpec.current_example)
  end

  def public_location(path = __FILE__, line = 12)
    instance_double(Thread::Backtrace::Location, absolute_path: path, path: path, lineno: line)
  end

  def native_fixture
    directory = Dir.mktmpdir('request-diagnostics-native-')
    File.chmod(0o700, directory)
    source = File.join(directory, 'fixture.rb')
    output = File.join(directory, 'result.json')
    stdout = File.join(directory, 'stdout')
    stderr = File.join(directory, 'stderr')
    support = File.expand_path('../support/request_exception_diagnostics.rb', __dir__)
    File.write(source, <<~RUBY)
      require 'rspec/core'
      require 'haveapi/context'
      require #{support.dump}
      class DiagnosticWorkerHooks; end
      HaveAPI::Hooks.register_hook(DiagnosticWorkerHooks, :exec_exception)
      RSpec.describe 'native diagnostic fixture', order: :defined do
        def record_fault
          env = { 'REQUEST_METHOD' => 'GET' }
          RequestExceptionDiagnostics::App.new(proc do |actual|
            context = HaveAPI::Context.new(nil, request: Struct.new(:env).new(actual))
            error = RuntimeError.new('never-output-secret')
            HaveAPI::Hooks.call_for(DiagnosticWorkerHooks, :exec_exception, args: [context, error])
            [500, {}, []]
          end).call(env)
        end
        it('passed') { record_fault }
        it('failed') { record_fault; raise 'intentional fixture failure' }
        it('pending') { record_fault; pending 'intentional'; raise 'expected pending failure' }
      end
      exit RSpec::Core::Runner.run(['--format', 'documentation', '--format', 'json', '--out', #{output.dump}])
    RUBY
    File.chmod(0o600, source)
    pid = nil
    waited = false
    primary = nil
    begin
      File.open(stdout, 'w', 0o600) do |out|
        File.open(stderr, 'w', 0o600) do |err|
          pid = Process.spawn(RbConfig.ruby, '-rbundler/setup', source, chdir: directory, out: out, err: err)
          _, status = Timeout.timeout(20) { Process.wait2(pid) }
          waited = true
          yield status, JSON.parse(File.read(output)), File.read(stdout)
        end
      end
    rescue Exception => e # rubocop:disable Lint/RescueException
      # Preserve the original assertion, wait error or signal over cleanup.
      primary = e
      raise
    ensure
      begin
        if pid && !waited
          begin
            Process.kill('KILL', pid)
          rescue Errno::ESRCH
            nil
          end
          Timeout.timeout(5) { Process.wait2(pid) }
          waited = true
        end
        FileUtils.remove_entry(directory) if waited || pid.nil?
      rescue StandardError
        raise unless primary
      end
    end
  end

  context 'with dispatcher and request identity' do
    %i[exec_exception request_exception].each do |name|
      it "observes #{name} before a real listener stops and preserves its result" do
        initial = { original: true }
        result = { stopped: true }
        request do |actual|
          expect(actual).to equal(env)
          returned = dispatch(name, error, actual, initial: initial) do |incoming, context, received|
            expect(incoming).to equal(initial)
            expect(context.request.env).to equal(env)
            expect(received).to equal(error)
            HaveAPI::Hooks.stop(result)
          end
          expect(returned).to equal(result)
          [409, {}, []]
        end
        event = packet.fetch('events').fetch(0)
        expect(event.values_at('dispatcher', 'http_status', 'request')).to eq([name.to_s, 409, 1])
      end
    end

    it 'delegates positional arguments, keywords and the same block exactly once' do
      target = Object.new
      seen = []
      target.define_singleton_method(:call_for) do |*arguments, **keywords, &block|
        seen << [arguments, keywords, block]
        HaveAPI::Hooks.call_for(*arguments, **keywords, &block)
      end
      target.singleton_class.prepend(described_class::Dispatcher)
      initial = {}
      arguments = [owner, :exec_exception, nil]
      kwargs = { args: [context_for(env), error], kwargs: { token: Object.new }, initial: initial, instance: false }
      block = proc { :unchanged }
      result = target.call_for(*arguments, **kwargs, &block)
      expect(result).to equal(initial)
      expect(seen.length).to eq(1)
      expect(seen.first[0].zip(arguments).all? { |a, b| a.equal?(b) }).to be(true)
      kwargs.each { |key, value| expect(seen.first[1].fetch(key)).to equal(value) }
      expect(seen.first[2]).to equal(block)
    end

    it 'preserves real initial-hash mutations and listener overrides' do
      initial = { count: 0 }
      request do
        result = dispatch(initial: initial) do |ret, *_|
          ret[:count] += 1
          { override: true }
        end
        expect(result).to equal(initial)
        expect(result).to eq(count: 1, override: true)
        [500, {}, []]
      end
      expect(packet.fetch('events').length).to eq(1)
    end

    it 'preserves a delegated error object and clears the request scope' do
      primary = ArgumentError.new('delegated')
      expect do
        request { dispatch { raise primary } }
      end.to(raise_error { |received| expect(received).to equal(primary) })
      expect(Thread.current.thread_variable_get(described_class::THREAD_KEY)).to be_nil
      expect(packet.fetch('events').first.fetch('http_status')).to eq('unavailable')
    end

    it 'preserves throws and restores nested scopes without assigning the inner env to the outer request' do
      inner = { 'REQUEST_METHOD' => 'GET' }
      returned = catch(:fixture_return) do
        request do
          dispatch
          request(inner) do
            dispatch(:request_exception, error, inner)
            [404, {}, []]
          end
          dispatch
          throw :fixture_return, :original
        end
      end
      expect(returned).to eq(:original)
      expect(Thread.current.thread_variable_get(described_class::THREAD_KEY)).to be_nil
      events = packet.fetch('events')
      expect(events.map { |event| event.values_at('request', 'http_status') }).to eq([[1, 'unavailable'], [2, 404], [1, 'unavailable']])
    end

    it 'calls the original app once and returns its exact untouched response and body' do
      body = instance_double(IO)
      allow(body).to receive(:each).and_raise('forbidden body read')
      allow(body).to receive(:close).and_raise('forbidden body close')
      response = [200, { 'fixture' => 'header' }, body]
      original = instance_double(Proc)
      allow(original).to receive(:call).with(env).and_return(response)
      expect(described_class::App.new(original).call(env)).to equal(response)
      expect(original).to have_received(:call).with(env).once
      expect(body).not_to have_received(:each)
      expect(body).not_to have_received(:close)
      expect(packet).to be_nil
    end

    it 'keeps both stages distinct and assigns successive requests their actual final status' do
      request do
        dispatch
        dispatch(:request_exception)
        [500, {}, []]
      end
      request do
        dispatch
        [422, {}, []]
      end
      events = packet.fetch('events')
      expect(events.map { |event| event.values_at('request', 'dispatcher', 'http_status') })
        .to eq([[1, 'exec_exception', 500], [1, 'request_exception', 500], [2, 'exec_exception', 422]])
    end

    it 'rejects unbound calls, wrong request environments and calls on another thread' do
      dispatch
      request do
        dispatch(:exec_exception, error, env.dup)
        thread = Thread.new { dispatch }
        expect(thread.join(3)).to equal(thread)
        thread.value
        [200, {}, []]
      end
      expect(packet).to be_nil
    end

    it 'does not install another dispatcher or reporter listener on repeated installation' do
      ancestors = HaveAPI::Hooks.singleton_class.ancestors
      allow(RSpec.configuration.reporter).to receive(:register_listener).and_raise('forbidden listener registration')
      described_class.install!
      described_class.install!
      expect(RSpec.configuration.reporter).not_to have_received(:register_listener)
      expect(HaveAPI::Hooks.singleton_class.ancestors).to eq(ancestors)
      expect(ancestors.count(described_class::Dispatcher)).to eq(1)
    end
  end

  context 'with privacy and fixed bounds' do
    it 'projects only enumerated public frames and never reads exception messages or method labels' do
      excluded = public_location('/tmp/private-sentinel.rb')
      config = public_location(File.expand_path('../../config/database.rb', __dir__))
      gem = Gem.loaded_specs.fetch('haveapi')
      gem_frame = public_location(File.join(gem.full_gem_path, 'lib/haveapi/hooks.rb'), 146)
      allow(error).to receive(:backtrace_locations).and_return([excluded, config, public_location, gem_frame])
      allow(error).to receive(:message).and_raise('forbidden exception message')
      allow(error).to receive(:full_message).and_raise('forbidden full exception message')
      allow(error).to receive(:inspect).and_raise('forbidden exception inspection')
      request do
        dispatch
        [500, {}, []]
      end
      expect(error).not_to have_received(:message)
      expect(error).not_to have_received(:full_message)
      expect(error).not_to have_received(:inspect)
      evidence = packet
      frames = evidence.fetch('events').first.fetch('exceptions').first.fetch('frames')
      expect(frames).to eq(
        [
          { 'source_id' => 'api/spec/smoke/request_exception_diagnostics_spec.rb', 'line' => 12 },
          { 'source_id' => 'haveapi/0.29.8/lib/haveapi/hooks.rb', 'line' => 146 }
        ]
      )
      serialized = JSON.generate(evidence)
      expect(serialized).not_to include('secret-sentinel', 'private-sentinel', 'SQL', RequestExceptionDiagnostics::ROOT)
      expect(evidence.fetch('example')).to match(%r{\Aapi/spec/smoke/request_exception_diagnostics_spec\.rb\[\d+(?::\d+)*\]\z})
    end

    it 'bounds causes, frame inspection and retained frames and detects cause cycles' do
      cause = ArgumentError.new('private-sentinel')
      allow(error).to receive_messages(cause: cause, backtrace_locations: Array.new(70) { public_location })
      allow(cause).to receive_messages(cause: error, backtrace_locations: nil)
      request do
        dispatch
        [500, {}, []]
      end
      objects = packet.fetch('events').first.fetch('exceptions')
      expect(objects.length).to eq(2)
      expect(objects.first.fetch('frames').length).to eq(6)
      expect(objects.first.fetch('trace')).to eq('bounded')
      expect(objects.last).to include('class' => 'ArgumentError', 'trace' => 'unavailable', 'cause_cycle' => true)
    end

    it 'does not inspect a fourth exception or a sixty-fifth location' do
      hidden = RuntimeError.new('hidden')
      third = TypeError.new('third')
      second = ArgumentError.new('second')
      allow(second).to receive(:cause).and_return(third)
      allow(third).to receive(:cause).and_return(hidden)
      allow(hidden).to receive(:backtrace_locations).and_raise('forbidden fourth exception trace')
      beyond = instance_double(Thread::Backtrace::Location)
      allow(beyond).to receive(:absolute_path).and_raise('forbidden sixty-fifth location')
      allow(error).to receive_messages(
        cause: second,
        backtrace_locations: Array.new(64) { public_location('/tmp/excluded') } + [beyond]
      )
      request do
        dispatch
        [500, {}, []]
      end
      expect(hidden).not_to have_received(:backtrace_locations)
      expect(beyond).not_to have_received(:absolute_path)
      objects = packet.fetch('events').first.fetch('exceptions')
      expect(objects.map { |object| object.fetch('class') }).to eq(%w[RuntimeError ArgumentError TypeError])
      expect(objects.first.fetch('frames')).to be_empty
      expect(objects.last.fetch('causes_truncated')).to be(true)
    end

    it 'uses fixed markers for anonymous classes, unknown methods, status and missing context' do
      anonymous = Class.new(StandardError).new('private-sentinel')
      request(env.merge('REQUEST_METHOD' => 'private-sentinel')) do |actual|
        dispatch(:exec_exception, anonymous, actual)
        HaveAPI::Hooks.call_for(owner, :request_exception, args: [nil, error])
        ['private-sentinel', {}, []]
      end
      evidence = packet
      expect(evidence.fetch('observation_error')).to be(true)
      expect(evidence.fetch('events').first).to include('method' => 'unknown', 'http_status' => 'unavailable')
      expect(evidence.fetch('events').first.fetch('exceptions').first.fetch('class')).to eq('unavailable')
      expect(JSON.generate(evidence)).not_to include('private-sentinel')
    end

    it 'limits each example to eight events and includes a fixed truncation flag' do
      request do
        12.times { dispatch }
        [500, {}, []]
      end
      evidence = packet
      expect(evidence.fetch('events').length).to eq(8)
      expect(evidence.fetch('truncated')).to be(true)
      expect((described_class::PREFIX + JSON.generate(evidence)).bytesize).to be <= described_class::MAX_BYTES
    end

    it 'enforces the serialized byte limit even for the longest enumerated frames and cause chains' do
      path = described_class.public_sources.max_by { |_, id| id.bytesize }.first
      cause = ArgumentError.new('private')
      third = TypeError.new('private')
      allow(error).to receive(:cause).and_return(cause)
      allow(cause).to receive(:cause).and_return(third)
      [error, cause, third].each { |exception| allow(exception).to receive(:backtrace_locations).and_return(Array.new(6) { public_location(path) }) }
      request do
        12.times { dispatch }
        [500, {}, []]
      end
      evidence = packet
      expect(evidence.fetch('truncated')).to be(true)
      expect((described_class::PREFIX + JSON.generate(evidence)).bytesize).to be <= described_class::MAX_BYTES
      expect(evidence.fetch('events').length).to be < 8
    end

    it 'records a fixed observer error without changing a stopped application result' do
      allow(described_class).to receive(:project_exception).and_raise(StandardError, 'never-output-secret')
      response = [409, {}, []]
      returned = request do
        dispatch { |ret, *_| HaveAPI::Hooks.stop(ret) }
        response
      end
      expect(returned).to equal(response)
      expect(packet).to include('events' => [], 'observation_error' => true)
    end

    it 'discards previous example state rather than retaining request objects in its packet' do
      request do
        dispatch
        [500, {}, []]
      end
      evidence = packet
      expect(evidence.keys).to contain_exactly('format', 'example', 'events', 'truncated', 'observation_error')
      expect(packet).to be_nil
      expect(Thread.current.thread_variable_get(described_class::THREAD_KEY)).to be_nil
      described_class.discard(RSpec.current_example)
      request do
        dispatch
        [404, {}, []]
      end
      expect(packet.fetch('events').first.fetch('request')).to eq(1)
    end

    it 'uses a fixed reporting fallback and clears state even when the reporter cannot accept messages' do
      request do
        dispatch
        [500, {}, []]
      end
      reporter = instance_double(RSpec::Core::Reporter)
      allow(reporter).to receive(:message).and_raise(StandardError, 'never-output-secret')
      listener = described_class::Listener.new(reporter)
      notification = RSpec::Core::Notifications::ExampleNotification.for(RSpec.current_example)
      expect { listener.example_failed(notification) }.not_to raise_error
      expect(reporter).to have_received(:message).twice
      expect(packet).to be_nil
    end
  end

  context 'with the actual memoized Rack app' do
    before { header 'Accept', 'application/json' }

    it 'uses the same wrapper repeatedly and preserves ordinary successful and authenticated responses' do
      expect(ApiAppHelper.app_instance).to equal(ApiAppHelper.app_instance)
      options '/'
      expect(last_response.status).to eq(200)
      as(SpecSeed.user) { get vpath('/users/current') }
      expect(last_response.status).to eq(200)
      expect(json.fetch('status')).to be(true)
      expect(packet).to be_nil
    end

    it 'preserves authentication refusal and ordinary domain validation without an exception event' do
      environment = SpecSeed.environment
      path = vpath("/environments/#{environment.id}")
      put path, JSON.generate(environment: { domain: '??' }), { 'CONTENT_TYPE' => 'application/json' }
      expect(last_response.status).to eq(401)
      as(SpecSeed.admin) do
        put path, JSON.generate(environment: { domain: '??' }), { 'CONTENT_TYPE' => 'application/json' }
      end
      expect(last_response.status).to eq(200)
      expect(json.fetch('status')).to be(false)
      expect(json.fetch('errors')).to have_key('domain')
      expect(packet).to be_nil
    end

    it 'captures an actual exec fault while leaving the generic HTTP envelope unchanged' do
      allow(VpsAdmin::API::Operations::Environment::Update).to receive(:run).and_raise(RuntimeError, 'controlled exec fault')
      as(SpecSeed.admin) do
        put vpath("/environments/#{SpecSeed.environment.id}"), JSON.generate(environment: { label: 'Controlled' }), { 'CONTENT_TYPE' => 'application/json' }
      end
      expect(last_response.status).to eq(500)
      expect(json.fetch('status')).to be(false)
      event = packet.fetch('events').find { |item| item['dispatcher'] == 'exec_exception' }
      expect(event).to include('http_status' => 500, 'method' => 'PUT')
      expect(event.fetch('exceptions').first.fetch('class')).to eq('RuntimeError')
    end

    it 'captures an actual request-stage authentication fault without changing its generic response' do
      path = vpath('/users/current')
      allow(VpsAdmin::API::Operations::Authentication::Password).to receive(:run).and_raise(RuntimeError, 'controlled request fault')
      as(SpecSeed.admin) { get path }
      expect(last_response.status).to eq(500)
      expect(json.fetch('status')).to be(false)
      event = packet.fetch('events').find { |item| item['dispatcher'] == 'request_exception' }
      expect(event).to include('http_status' => 500, 'method' => 'GET')
      expect(event.fetch('exceptions').first.fetch('class')).to eq('RuntimeError')
    end
  end

  it 'emits only failed-example packets through the ordinary documentation and native JSON formatters' do
    native_fixture do |status, evidence, stdout|
      expect(status.exitstatus).to eq(1)
      expect(evidence.fetch('summary')).to include('example_count' => 3, 'failure_count' => 1, 'pending_count' => 1)
      messages = evidence.fetch('messages').grep(/^#{described_class::PREFIX}/)
      expect(messages.length).to eq(1)
      diagnostic = JSON.parse(messages.first.delete_prefix(described_class::PREFIX))
      expect(diagnostic.fetch('events').length).to eq(1)
      expect(diagnostic.fetch('events').first.fetch('request')).to eq(1)
      expect(stdout.scan(described_class::PREFIX).length).to eq(1)
      expect(messages.join).not_to include('never-output-secret')
    end
  end

  context 'with effective CI dependency companions' do
    def with_lock(bytes = public_lock)
      Dir.mktmpdir('ci-environment-') do |root|
        Dir.mkdir(File.join(root, 'tmp'))
        lock = File.join(root, 'Gemfile.lock')
        File.binwrite(lock, bytes)
        allow(Bundler).to receive(:default_lockfile).and_return(Pathname.new(lock))
        yield root, lock
      end
    end

    def public_lock(remote = 'https://rubygems.org/')
      <<~LOCK
        GEM
          remote: #{remote}
          specs:
            rake (13.0.0)

        PLATFORMS
          ruby

        DEPENDENCIES
          rake

        BUNDLED WITH
           #{Bundler::VERSION}
      LOCK
    end

    %w[full core].each do |mode|
      it "captures #{mode} exact lock bytes, digest and effective resolved versions using the existing workflow labels" do
        with_lock do |root, lock|
          evidence = SpecCiEnvironment.capture(mode: mode, topic: 'foundation', api_root: root)
          expect(File.binread(File.join(root, 'tmp', "rspec-Gemfile-#{mode}-foundation.lock"))).to eq(File.binread(lock))
          expect(evidence.fetch(:gemfile_lock_sha256)).to eq(Digest::SHA256.file(lock).hexdigest)
          json = JSON.parse(File.read(File.join(root, 'tmp', "rspec-environment-#{mode}-foundation.json")))
          expect(json).to include('mode' => mode, 'topic' => 'foundation', 'ruby' => RUBY_DESCRIPTION, 'bundler' => Bundler::VERSION,
                                  'rspec' => RSpec::Core::Version::STRING, 'rubygems' => Gem::VERSION)
          expected = Bundler.load.specs.map { |spec| [spec.name, spec.version.to_s, spec.platform.to_s] }.sort
          expect(json.fetch('resolved_specs').map { |spec| spec.values_at('name', 'version', 'platform') }).to eq(expected)
        end
      end
    end

    [['wrong', 'foundation'], ['full', '../secret'], ['core', 'unknown-topic']].each do |mode, topic|
      it "refuses invalid mode/topic #{mode}/#{topic} before writing companions" do
        with_lock do |root, _|
          expect { SpecCiEnvironment.capture(mode: mode, topic: topic, api_root: root) }.to raise_error(SpecCiEnvironment::Invalid)
          expect(Dir.children(File.join(root, 'tmp'))).to be_empty
        end
      end
    end

    ['https://user:secret-sentinel@rubygems.org/', 'https://private.example/', 'http://rubygems.org/'].each do |remote|
      it "refuses an unsafe remote form #{remote.split(':').first} without a content excerpt" do
        with_lock(public_lock(remote)) do |root, _|
          expect { SpecCiEnvironment.capture(mode: 'full', topic: 'foundation', api_root: root) }
            .to raise_error(SpecCiEnvironment::Invalid, 'RSpec environment evidence unavailable')
          expect(Dir.children(File.join(root, 'tmp'))).to be_empty
        end
      end
    end

    ['GIT', 'PATH', 'PLUGIN SOURCE', 'UNKNOWN SOURCE'].each do |section|
      it "refuses the unsupported #{section} source section" do
        with_lock(public_lock + "\n#{section}\n  remote: never-output-secret\n  specs:\n") do |root, _|
          expect { SpecCiEnvironment.capture(mode: 'core', topic: 'foundation', api_root: root) }
            .to raise_error(SpecCiEnvironment::Invalid, 'RSpec environment evidence unavailable')
          expect(Dir.children(File.join(root, 'tmp'))).to be_empty
        end
      end
    end

    it 'refuses another effective lock and a symlink rather than substituting package bytes' do
      with_lock do |root, lock|
        allow(Bundler).to receive(:default_lockfile).and_return(Pathname.new(File.join(root, 'other.lock')))
        expect { SpecCiEnvironment.capture(mode: 'core', topic: 'foundation', api_root: root) }.to raise_error(SpecCiEnvironment::Invalid)
        allow(Bundler).to receive(:default_lockfile).and_return(Pathname.new(lock))
        File.rename(lock, File.join(root, 'owned.lock'))
        File.symlink('owned.lock', lock)
        expect { SpecCiEnvironment.capture(mode: 'core', topic: 'foundation', api_root: root) }.to raise_error(SpecCiEnvironment::Invalid)
        expect(Dir.children(File.join(root, 'tmp'))).to be_empty
      end
    end

    it 'refuses oversized locks and existing output files without replacing them' do
      with_lock('x' * (SpecCiEnvironment::MAX_LOCK_BYTES + 1)) do |root, _|
        expect { SpecCiEnvironment.capture(mode: 'full', topic: 'foundation', api_root: root) }.to raise_error(SpecCiEnvironment::Invalid)
        expect(Dir.children(File.join(root, 'tmp'))).to be_empty
      end
      with_lock do |root, _|
        path = File.join(root, 'tmp', 'rspec-Gemfile-full-foundation.lock')
        File.write(path, 'retained')
        expect { SpecCiEnvironment.capture(mode: 'full', topic: 'foundation', api_root: root) }.to raise_error(SpecCiEnvironment::Invalid)
        expect(File.read(path)).to eq('retained')
      end
    end

    it 'reports failed artifact publication separately and never emits the underlying error' do
      with_lock do |root, _|
        allow(File).to receive(:link).and_raise(Errno::EACCES, 'never-output-secret')
        expect { SpecCiEnvironment.capture(mode: 'full', topic: 'foundation', api_root: root) }
          .to raise_error(SpecCiEnvironment::Invalid, 'RSpec environment evidence unavailable')
        expect(Dir.children(File.join(root, 'tmp'))).to be_empty
      end
    end
  end
end
