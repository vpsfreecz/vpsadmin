# frozen_string_literal: true

require 'cgi'

RSpec.describe VpsAdmin::API do
  let(:server) { app.settings.api_server }
  let(:default_api_version) { server.default_version }
  let(:default_api_path) { server.version_prefix(default_api_version) }

  after do
    header 'Accept-Language', nil
    header 'Cookie', nil
    header 'X-HaveAPI-Auth-Token', nil
  end

  def documentation(page: nil, resource: nil, locale: 'en')
    header 'Accept', 'text/html'
    header 'Accept-Language', locale
    params = resource ? { resource: } : { page: page || 'overview' }
    get '/', params, { 'HTTPS' => 'on' }
    expect(last_response.status).to eq(200)
    CGI.unescapeHTML(last_response.body)
  end

  def panel(html, id)
    html.split(/<details\b[^>]*\bid="#{Regexp.escape(id)}"/, 2).fetch(1).split('</details>', 2).first
  end

  # Avoid constructing a diff of the entire version page on an assertion failure.
  def expect_text(html, *values)
    values.each { |value| expect(html.include?(value)).to be(true), "Missing documentation text: #{value}" }
  end

  def reject_text(html, *values)
    values.each { |value| expect(html.include?(value)).to be(false), "Unexpected documentation text: #{value}" }
  end

  it 'mounts the matching generators for API 7.0 only', :documentation_profile do
    expect(HaveAPI::GoClient::VERSION).to eq(HaveAPI::VERSION)
    expect(HaveAPI::RustClient::VERSION).to eq(HaveAPI::VERSION)
    expect(HaveAPI::TypeScriptClient::VERSION).to eq(HaveAPI::VERSION)
    expect(server.documentation_client_profiles('7.0').keys).to contain_exactly(:go, :rust, :typescript)
    expect(server.documentation_client_profiles('6.0')).to be_empty
  end

  it 'renders registry initialization with the mounted Rust profile', :documentation_profile do
    profile = server.documentation_client_profiles(default_api_version).fetch(:rust)
    context = HaveAPI::ClientExample::Context.new(
      version: default_api_version, host: 'example.org', base_url: 'https://example.org/',
      version_url: "https://example.org#{default_api_path}", description: {}, profile:
    )
    expect(profile.package_version).to be_nil

    {
      HaveAPI::ClientExamples::RustAsyncClient => ['// cargo add vpsadmin-client', 'use vpsadmin_client::Client;'],
      HaveAPI::ClientExamples::RustBlockingClient => [
        '// cargo add vpsadmin-client --features blocking', 'use vpsadmin_client::blocking::Client;'
      ]
    }.each do |renderer, (installation, import)|
      result = renderer.render(:init, context:)
      expect(result.fetch(:status)).to eq(:code)
      code = result.fetch(:code)
      expect(code.lines.first.chomp).to eq(installation)
      expect_text(code, import)
      reject_text(code, 'https://github.com/vpsfreecz/vpsadmin-rust-client',
                  'ff876abe17e3301da62c1b6afbda055ec89db9d2', 'version =', 'git =', 'rev =')
      if renderer == HaveAPI::ClientExamples::RustAsyncClient
        expect_text(code, '#[tokio::main]', 'async fn main()')
      else
        expect_text(code, 'fn main()', 'outside async runtime threads')
        reject_text(code, '#[tokio::main]', 'async fn main()')
      end
    end
  end

  it 'renders existing Go token authentication through the mounted automatic profile', :documentation_profile do
    description = server.describe_version(HaveAPI::Context.new(server, version: default_api_version, user: nil, doc: true))
    token = description.fetch(:authentication).fetch(:token)
    serialized = JSON.parse(JSON.generate(description), symbolize_names: true)
    expect(token.fetch(:query_parameter)).to eq(:_auth_token)
    expect(serialized.fetch(:authentication).fetch(:token).fetch(:query_parameter)).to eq('_auth_token')
    expect(token.fetch(:http_header)).to eq('X-HaveAPI-Auth-Token')

    profile = server.documentation_client_profiles(default_api_version).fetch(:go)
    context = HaveAPI::ClientExample::Context.new(
      version: default_api_version, host: 'example.org', base_url: 'https://example.org/',
      version_url: "https://example.org#{default_api_path}", description:, profile:
    )
    result = HaveAPI::ClientExamples::GoClient.render(:auth, context:, auth_method: :token, auth_description: token)
    expect(result.fetch(:status)).to eq(:code)
    expect_text(result.fetch(:code), 'api.SetExistingTokenAuth("example-token")',
                'github.com/vpsfreecz/vpsadmin-go-client/client')
    reject_text(result.fetch(:code), 'This authentication method does not match the configured Go SDK.')
  end

  it 'renders generated TypeScript initialization and an authorized public action', :documentation_profile do
    header 'Accept', 'application/json'
    as(SpecSeed.user) { options '/?describe=default' }
    expect(last_response.status).to eq(200)
    description = JSON.parse(last_response.body, symbolize_names: true).fetch(:response)
    profile = server.documentation_client_profiles(default_api_version).fetch(:typescript)
    expect(profile.package_version).to be_nil
    version_url = "#{last_request.base_url}#{default_api_path}"
    context = HaveAPI::ClientExample::Context.new(
      version: default_api_version, host: last_request.host, base_url: "#{last_request.base_url}/",
      version_url:, description:, profile:
    )
    renderer = HaveAPI::ClientExamples::TsGeneratedClient
    initialization = renderer.render(:init, context:)
    expect(initialization.fetch(:status)).to eq(:code)
    expect_text(initialization.fetch(:code), 'import { createClient } from "vpsadmin-typescript-client";',
                %(new AsyncClient("#{version_url.chomp('/')}")))
    reject_text(initialization.fetch(:code), last_request.url)

    resource = description.fetch(:resources).fetch(:cluster)
    action = resource.fetch(:actions).fetch(:public_stats)
    result = renderer.render(:example, context: context.with(
      resource_path: ['cluster'], resource:, action_name: 'public_stats', action:,
      sample: action.fetch(:examples).first
    ))
    expect(result.fetch(:status)).to eq(:code)
    expect_text(result.fetch(:code), 'api.cluster.public_stats()', 'result.data')
  end

  it 'renders the actual VPS Index example through the mounted Go profile', :documentation_profile do
    description = server.describe_version(HaveAPI::Context.new(server, version: default_api_version, user: nil, doc: true))
    resource = description.fetch(:resources).fetch('vps')
    action = resource.fetch(:actions).fetch('index')
    context = HaveAPI::ClientExample::Context.new(
      version: default_api_version, host: 'example.org', base_url: 'https://example.org/',
      version_url: "https://example.org#{default_api_path}", description:,
      profile: server.documentation_client_profiles(default_api_version).fetch(:go),
      resource_path: ['vps'], resource:, action_name: 'index', action:,
      sample: action.fetch(:examples).first, detail: :thorough
    )
    result = HaveAPI::ClientExamples::GoClient.render(:example, context:)
    expect(result.fetch(:status)).to eq(:code)
    expect_text(result.fetch(:code), 'github.com/vpsfreecz/vpsadmin-go-client/client')
  end

  it 'serves anonymous overview, authentication and resource pages without API-header identity' do
    html = as(SpecSeed.admin) { documentation }
    expect_text(html, 'init-go', 'init-rust-async', 'init-rust-blocking',
                'init-typescript-generated', 'init-typescript-callback', 'init-typescript-async')
    reject_text(html, 'docs-identity', 'data-documentation-login')
    expect_text(panel(html, 'init-typescript-generated'), 'createClient', 'vpsadmin-typescript-client',
                'haveapi-client')
    expect_text(panel(html, 'init-go'), 'go get github.com/vpsfreecz/vpsadmin-go-client/client@latest')
    expect_text(panel(html, 'init-rust-async'), '// cargo add vpsadmin-client')
    expect_text(panel(html, 'init-rust-blocking'), '// cargo add vpsadmin-client --features blocking')
    reject_text(html, 'https://github.com/vpsfreecz/vpsadmin-rust-client',
                'ff876abe17e3301da62c1b6afbda055ec89db9d2', 'version = "latest"',
                'haveapi.invalid', 'snapshot_path', 'generator_config_path')
    auth = documentation(page: 'authentication')
    expect_text(panel(auth, 'auth-token-go'), 'SetExistingTokenAuth("example-token")')
    expect_text(panel(auth, 'auth-token-typescript-generated'),
                %(runtime.authenticate("token", { token: "example-token" })))
    cluster = documentation(resource: 'cluster')
    expect_text(panel(cluster, 'example-cluster-public_stats-0-go'), 'api.Cluster.PublicStats')
    expect_text(panel(cluster, 'example-cluster-public_stats-0-rust-async'), '.cluster().public_stats()')
    expect_text(panel(cluster, 'example-cluster-public_stats-0-rust-blocking'), '.cluster().public_stats()')
    expect_text(panel(cluster, 'example-cluster-public_stats-0-typescript-generated'),
                'api.cluster.public_stats()')
    expect_text(cluster, 'data-doc-section', 'class="docs-permalink"', 'data-example-details=')
    example_details = cluster.match(/data-example-details="(\{[^}]+\})"/).captures.first
    expect(JSON.parse(example_details).keys).to include('go', 'rust-async', 'typescript-generated')
    expect_text(documentation(resource: 'node'), 'id="root-node-update"')
    expect(User.current).to be_nil
    expect(UserSession.current).to be_nil
    expect(PaperTrail.request.whodunnit).to be_nil
  end

  it 'normalizes only known slashless version GETs and serves neutral packaged guides' do
    header 'Accept', 'text/html'
    get "#{default_api_path.chomp('/')}?page=resources&q=a%2Bb"
    expect(last_response.status).to eq(308)
    expect(last_response.headers.fetch('location')).to end_with("#{default_api_path}?page=resources&q=a%2Bb")
    expect(server.versions).not_to include('99.0')
    get '/v99.0'
    expect(last_response.status).to eq(406)
    expect(last_response.headers).not_to have_key('location')
    get '/_login?return=https://invalid.example/'
    expect(last_response.status).to eq(303)
    expect(last_response.headers.fetch('location')).to end_with(default_api_path)
    expect(last_response.headers).not_to have_key('www-authenticate')
    %w[/doc /doc/index /doc/index.md /doc/readme].each do |path|
      as(SpecSeed.admin) { get path }
      expect(last_response.status).to eq(200)
      expect(last_response.headers.fetch('cache-control')).to include('no-store')
      expect_text(last_response.body, 'HaveAPI', 'self-descriptive RESTful')
      reject_text(last_response.body, 'docs-identity', 'data-documentation-login')
    end
  end

  context 'with configured documentation OAuth' do
    let(:app) do
      original = described_class.instance_variable_get(:@configure)
      allow(SysConfig).to receive(:get).and_call_original
      allow(SysConfig).to receive(:get).with(:core, :auth_url).and_return('https://example.org')
      described_class.configure do |api|
        original&.call(api)
        api.documentation_oauth(
          client_id: 'disposable-documentation-client', client_secret: 'disposable-secret',
          session_secret: 's' * 64, scope: ['all'], session_lifetime: 3600,
          redirect_uri: 'https://example.org/_documentation/oauth/callback'
        )
      end
      described_class.default.app
    ensure
      described_class.configure(&original)
    end

    def documentation_cookie(user)
      user.update!(enable_oauth2_auth: true, lockout: false, password_reset: false)
      session = create_open_session!(user:, auth_type: 'oauth2')
      handler = Struct.new(:response).new(Rack::Response.new)
      server.documentation_oauth.send(:write_cookie, handler, 'session', {
                                       'token' => session.token.token, 'expires' => Time.now.to_f + 3600,
                                       'csrf' => 'c' * 64
                                     })
      Array(handler.response.headers.fetch('set-cookie')).first.split(';', 2).first
    end

    it 'keeps cookie identity, member privacy, locale and ordinary OPTIONS authentication separate' do
      header 'Cookie', documentation_cookie(SpecSeed.user)
      member = as(SpecSeed.admin) { documentation(resource: 'node', locale: 'cs') }
      expect(User.current).to eq(SpecSeed.user)
      expect(PaperTrail.request.whodunnit.to_s).to eq(SpecSeed.user.id.to_s)
      reject_text(member, 'id="root-node-update"', 'example-node-update-0-',
                  '<code>ip_addr</code>', '192.168.0.10', 'translation missing:')
      expect(last_response.headers.fetch('vary')).to include('Accept-Language')
      expect_text(member, 'Nečinnost CPU')
      header 'Authorization', 'Basic invalid'
      documentation(page: 'resources', locale: 'cs')
      expect(User.current).to eq(SpecSeed.user)
      header 'Authorization', nil
      header 'Accept', 'application/json'
      options default_api_path
      expect(last_response.status).to eq(200)
      expect(User.current).to be_nil
      as(SpecSeed.admin) { options default_api_path }
      expect(last_response.status).to eq(200)
      expect(User.current).to eq(SpecSeed.admin)
      header 'Cookie', documentation_cookie(SpecSeed.admin)
      expect_text(documentation(resource: 'node'), 'id="root-node-update"', '<code>ip_addr</code>')
      header 'Cookie', nil
      as(SpecSeed.admin) { documentation(resource: 'node') }
      expect(User.current).to be_nil
      expect(UserSession.current).to be_nil
      expect(PaperTrail.request.whodunnit).to be_nil
    end
  end
end
