# frozen_string_literal: true

require 'cgi'

RSpec.describe VpsAdmin::API do
  let(:server) { app.settings.api_server }

  after do
    header 'Accept-Language', nil
  end

  def documentation(locale: 'en')
    header 'Accept', 'text/html'
    header 'Accept-Language', locale
    get '/v7.0/'
    expect(last_response.status).to eq(200)
    CGI.unescapeHTML(last_response.body)
  end

  def panel(html, id)
    html.split(%(<div id="#{id}">), 2).fetch(1).split('</div>', 2).first
  end

  # Avoid constructing a diff of the entire version page on an assertion failure.
  def expect_text(html, *values)
    values.each { |value| expect(html.include?(value)).to be(true), "Missing documentation text: #{value}" }
  end

  def reject_text(html, *values)
    values.each { |value| expect(html.include?(value)).to be(false), "Unexpected documentation text: #{value}" }
  end

  it 'mounts the released generators for API 7.0 only', :documentation_profile do
    expect(HaveAPI::GoClient::VERSION).to eq(HaveAPI::VERSION)
    expect(HaveAPI::RustClient::VERSION).to eq(HaveAPI::VERSION)
    expect(server.documentation_client_profiles('7.0').keys).to contain_exactly(:go, :rust)
    expect(server.documentation_client_profiles('6.0')).to be_empty
  end

  it 'renders registry initialization with the mounted Rust profile', :documentation_profile do
    profile = server.documentation_client_profiles('7.0').fetch(:rust)
    context = HaveAPI::ClientExample::Context.new(
      version: '7.0', host: 'example.org', base_url: 'https://example.org/',
      version_url: 'https://example.org/v7.0/', description: {}, profile:
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

  it 'renders the SDK programs and preserves visibility and locale between requests' do
    admin_html = as(SpecSeed.admin) { documentation }
    expect_text(admin_html, 'id="root-node-update"')

    member_html = as(SpecSeed.user) { documentation(locale: 'cs') }
    expect_text(member_html, 'init-go', 'init-rust-async', 'init-rust-blocking')
    reject_text(member_html, 'id="root-node-update"', 'example-node-update-0-', 'translation missing:')
    node_index = member_html.split('id="root-node-index"', 2).fetch(1).split('<h3', 2).first
    reject_text(node_index, '<td>ip_addr</td>', '192.168.0.10')
    reject_text(member_html, 'haveapi.invalid', 'snapshot_path', 'generator_config_path')

    html = documentation
    expect_text(html, 'Rust (async and blocking)', 'github.com/vpsfreecz/vpsadmin-go-client/client')
    expect_text(panel(html, 'init-go'), 'go get github.com/vpsfreecz/vpsadmin-go-client/client@latest')
    expect_text(panel(html, 'init-rust-async'), '// cargo add vpsadmin-client')
    expect_text(panel(html, 'init-rust-blocking'), '// cargo add vpsadmin-client --features blocking')
    %w[init-rust-async init-rust-blocking].each do |id|
      reject_text(panel(html, id), 'https://github.com/vpsfreecz/vpsadmin-rust-client',
                  'ff876abe17e3301da62c1b6afbda055ec89db9d2', 'version =')
    end
    reject_text(html, 'version = "latest"',
                'haveapi.invalid', 'snapshot_path', 'generator_config_path')

    expect_text(panel(html, 'example-cluster-public_stats-0-go'), 'api.Cluster.PublicStats', 'VpsCount')
    expect_text(panel(html, 'example-cluster-public_stats-0-rust-async'), '.cluster().public_stats()', '.send().await?')
    expect_text(panel(html, 'example-cluster-public_stats-0-rust-blocking'), '.cluster().public_stats()', '.send()?')
    expect_text(html, 'HAVEAPI_USER', 'HAVEAPI_PASSWORD', 'HAVEAPI_TOKEN')
  end
end
