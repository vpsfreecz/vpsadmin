# frozen_string_literal: true

RSpec.describe ApiAppHelper do
  let(:secret) { 'DIAGNOSTIC_SECRET_SENTINEL' }
  let(:prefix) { 'API_SPEC_REQUEST_EXCEPTION ' }
  let(:server) { described_class.app_instance.settings.api_server }

  def raised(error, cause: nil)
    raise error, cause: cause
  rescue StandardError => e
    e
  end

  def capture_stderr(&block)
    captured = nil
    expect(&block).to output(satisfy { |text| captured = text }).to_stderr
    captured
  end

  def diagnostic(text)
    expect(text.lines.length).to eq(1)
    expect(text).to start_with(prefix)
    expect(text).not_to include(secret)
    JSON.parse(text.delete_prefix(prefix))
  end

  def fail_basic_auth(error)
    allow(VpsAdmin::API::Operations::Authentication::Password).to receive(:run).and_raise(error)
  end

  def request_current
    path = vpath('/users/current')
    header 'Accept', 'application/json'
    header 'X-Diagnostic-Secret', secret
    as(SpecSeed.admin, password: secret) do
      get path, { diagnostic_secret: secret },
          'CONTENT_TYPE' => 'application/json', 'rack.input' => StringIO.new(JSON.generate(secret: secret))
    end
  end

  def expect_generic_error
    expect(last_response.status).to eq(500)
    expect(json).to eq('status' => false, 'response' => nil, 'errors' => nil,
                       'message' => HaveAPI.t('haveapi.errors.server_error'))
  end

  it 'runs the test suite' do
    expect(1 + 1).to eq(2)
  end

  it 'reports safe cause metadata once through the cached app without changing the response' do
    database_error = Mysql2::Error.new("SELECT password FROM secret_table WHERE token='#{secret}'")
    allow(database_error).to receive_messages(error_number: 1205, sql_state: 'HY000')
    fail_basic_auth(raised(StandardError.new(secret), cause: raised(database_error)))
    cached = described_class.app_instance
    3.times { expect(described_class.app_instance).to equal(cached) }

    data = diagnostic(capture_stderr { request_current })

    expect_generic_error
    expect(data.keys).to contain_exactly('causes', 'example_id')
    expect(data['example_id']).to eq(RSpec.current_example.id)
    expect(data['causes'].map { |entry| entry['class'] }).to eq(['StandardError', 'Mysql2::Error'])
    expect(data['causes'].last).to include('errno' => 1205, 'sqlstate' => 'HY000')
    data['causes'].each do |entry|
      expect(entry.keys - %w[class file line errno sqlstate]).to be_empty
      expect(entry).to include('file' => 'api/spec/smoke/harness_spec.rb', 'line' => be_a(Integer))
    end
  end

  it 'preserves a nonempty hook return and omits absent exception metadata' do
    original = { http_status: 503, message: secret }
    result = nil
    text = capture_stderr do
      result = server.call_instance_hooks_for(
        :request_exception,
        args: [Object.new, StandardError.new(secret)],
        initial: original
      )
    end

    expect(result).to equal(original)
    expect(result).to eq(http_status: 503, message: secret)
    expect(diagnostic(text)['causes']).to eq([{ 'class' => 'StandardError' }])
  end

  it 'emits no diagnostic for ordinary successful authentication' do
    expect { as(SpecSeed.admin) { get vpath('/users/current') } }.not_to output.to_stderr
    expect(last_response.status).to eq(200)
  end

  it 'bounds the cause chain to four entries' do
    error = 6.times.reduce(nil) { |cause, _| raised(StandardError.new(secret), cause: cause) }
    text = capture_stderr { server.call_instance_hooks_for(:request_exception, args: [nil, error]) }

    expect(diagnostic(text)['causes'].length).to eq(4)
  end

  it 'omits outside and eval locations and invalid MySQL metadata' do
    outside = begin
      JSON.parse('{')
    rescue JSON::ParserError => e
      e.backtrace_locations.first
    end
    evaluated = begin
      eval('raise StandardError', binding) # rubocop:disable Style/EvalWithLocation -- exercise a real eval backtrace location
    rescue StandardError => e
      e
    end
    error = Mysql2::Error.new(secret)
    allow(error).to receive_messages(backtrace_locations: [evaluated.backtrace_locations.first, outside],
                                     error_number: secret, sql_state: secret)
    text = capture_stderr { server.call_instance_hooks_for(:request_exception, args: [nil, error]) }

    expect(diagnostic(text)['causes']).to eq([{ 'class' => 'Mysql2::Error' }])
  end

  it 'omits an absent current example' do
    allow(RSpec).to receive(:current_example).and_return(nil)
    text = capture_stderr { server.call_instance_hooks_for(:request_exception, args: [nil, StandardError.new(secret)]) }

    expect(diagnostic(text).keys).to eq(['causes'])
  end

  it 'contains reporter failures without replacing the API error or leaking their messages' do
    fail_basic_auth(StandardError.new(secret))
    allow(described_class).to receive(:diagnostic_causes).and_raise(StandardError, secret)

    expect(diagnostic(capture_stderr { request_current })).to eq('diagnostic_failed' => true)
    expect_generic_error

    allow(described_class).to receive(:warn).and_raise(IOError, secret)
    expect { request_current }.not_to raise_error
    expect_generic_error
  end
end
