# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe VpsAdmin::API::Authentication::Appearance do
  let(:branding) { {} }

  let(:logo_directory) { Dir.mktmpdir('authentication-logo') }

  after { FileUtils.remove_entry(logo_directory) }

  def image_file(name, bytes)
    File.join(logo_directory, name).tap { |path| File.binwrite(path, bytes) }
  end

  before do
    allow(VpsAdmin::API::DeploymentConfig).to receive(:dig) do |category, key|
      branding[key] if category == 'authentication'
    end
  end

  it 'accepts only scalar preferences and the exact independent return capability' do
    %w[light dark auto].each do |theme|
      expect(described_class.preference('theme' => theme)).to eq(theme)
    end
    [nil, '', 'system', 'DARK', ['dark'], { 'dark' => '1' }].each do |theme|
      expect(described_class.preference(theme:)).to be_nil
    end
    expect(described_class.return_theme?(theme: 'dark')).to be(false)
    expect(described_class.return_theme?(theme_return: '1')).to be(true)
    [1, true, ['1'], 'true'].each do |value|
      expect(described_class.return_theme?(theme_return: value)).to be(false)
    end
  end

  it 'prefers a scheme file over the common file and keeps public paths fixed' do
    common = image_file('common.png', 'common')
    light = image_file('light.webp', 'light')
    branding.merge!('logo_file' => common, 'light_logo_file' => light)
    expect(described_class.logo('light')).to eq(file: light, type: 'image/webp')
    expect(described_class.logo('dark')).to eq(file: common, type: 'image/png')
    expect(described_class.brand).to include('src="/_auth/appearance/logo/light"', 'src="/_auth/appearance/logo/dark"')
    expect(described_class.brand).not_to include(logo_directory)
    branding['light_logo_file'] = image_file('invalid.txt', 'invalid')
    expect(described_class.logo('light')[:file]).to eq(common)
  end

  it 'ignores unavailable, unsupported and non-file values and uses the inline wordmark' do
    [nil, '', 'https://example.test/logo.png', 'relative.png', ['logo.png'],
     File.join(logo_directory, 'missing.png'), logo_directory, image_file('logo.txt', 'x')].each do |value|
      branding['logo_file'] = value
      expect(described_class.logo('light')).to be_nil
      expect(described_class.brand).to include('aria-label="vpsAdmin"', 'fill="currentColor"')
      expect(described_class.brand).not_to include('<img')
    end
    expect(described_class.logo('../light')).to be_nil
  end

  it 'ignores dormant sysconfig and URL keys and keeps registration light only' do
    SysConfig.create!(category: 'core', name: 'logo_url', data_type: 'String', value: 'https://legacy.example.test/logo')
    branding['logo_url'] = 'https://external.example.test/logo.png'
    expect(described_class.brand).not_to include('<img')
    branding['logo_file'] = image_file('common.png', 'image')
    expect(described_class.brand(scheme: 'light').scan('<img').size).to eq(1)
    expect(described_class.brand(scheme: 'light')).not_to include('/logo/dark')
  end

  it 'serves exact public bytes with content-based validators and matching HEAD behavior' do
    bytes = "\x89PNG\r\n\x1a\npublic image".b
    path = image_file('logo.png', bytes)
    branding['logo_file'] = path
    get '/_auth/appearance/logo/light', file: '/etc/passwd', theme: 'dark'
    expect(last_response.status).to eq(200)
    expect(last_response.body.b).to eq(bytes)
    expect(last_response.headers['Content-Type']).to eq('image/png')
    expect(last_response.headers['Content-Disposition']).to eq('inline')
    expect(last_response.headers['X-Content-Type-Options']).to eq('nosniff')
    expect(last_response.headers['Cache-Control']).to eq('public, max-age=0, must-revalidate')
    expect(last_response.headers['Set-Cookie']).to be_nil
    tag = last_response.headers.fetch('ETag')
    head '/_auth/appearance/logo/light'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to be_empty
    # Rack::Test finishes its buffered empty HEAD body and rewrites its copy's
    # length. Check the original headers returned by the actual Rack app.
    expect(last_response.original_headers['content-length']).to eq(bytes.bytesize.to_s)
    expect(last_response.headers['ETag']).to eq(tag)
    get '/_auth/appearance/logo/light', {}, 'HTTP_IF_NONE_MATCH' => tag
    expect(last_response.status).to eq(304)
    expect(last_response.body).to be_empty
    head '/_auth/appearance/logo/light', {}, 'HTTP_IF_NONE_MATCH' => tag
    expect(last_response.status).to eq(304)
    expect(last_response.body).to be_empty
    timestamp = File.mtime(path)
    File.binwrite(path, 'changed')
    File.utime(timestamp, timestamp, path)
    get '/_auth/appearance/logo/light', {}, 'HTTP_IF_NONE_MATCH' => tag
    expect(last_response.status).to eq(200)
    expect(last_response.body).to eq('changed')
    expect(last_response.headers['ETag']).not_to eq(tag)
  end

  it 'maps each supported MIME type and permits self-contained inline-style SVG' do
    svg = '<svg xmlns="http://www.w3.org/2000/svg"><style>.logo{fill:red}</style><path class="logo" d="M0 0h1v1z"/></svg>'
    { 'png' => 'image/png', 'jpg' => 'image/jpeg', 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp', 'svg' => 'image/svg+xml' }.each do |extension, mime|
      bytes = extension == 'svg' ? svg : "image-#{extension}"
      branding['dark_logo_file'] = image_file("logo.#{extension}", bytes)
      get '/_auth/appearance/logo/dark'
      expect(last_response.status).to eq(200)
      expect(last_response.headers['Content-Type']).to eq(mime)
      expect(last_response.body).to eq(bytes)
      expect(last_response.headers['Content-Security-Policy'])
        .to eq("default-src 'none'; style-src 'unsafe-inline'; sandbox; base-uri 'none'; form-action 'none'")
    end
  end

  it 'returns 404 for unavailable and non-finite targets without exposing paths' do
    branding['logo_file'] = image_file('logo.png', 'image')
    File.unlink(branding['logo_file'])
    %w[/_auth/appearance/logo/light /_auth/appearance/logo/auto /_auth/appearance/logo/light/extra
       /_auth/appearance/logo/%2e%2e%2fetc%2fpasswd].each do |path|
      get path
      expect(last_response.status).to eq(404)
      expect(last_response.body).not_to include(logo_directory)
    end
  end
end
