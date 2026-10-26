# frozen_string_literal: true

require_relative 'safety'
require_relative 'snapshot'

RSpec.describe VpsAdmin::SchemaExport::Snapshot do
  let(:description) do
    {
      'help' => '/v7.0/', 'authentication' => {}, 'meta' => {},
      'resources' => {
        'example' => {
          'resources' => {}, 'actions' => {
            'show' => {
              'scope' => 'example#show', 'method' => 'GET', 'path' => '/v7.0/examples/{example_id}',
              'description' => 'omit prose', 'examples' => [{ 'private' => 'omit examples' }],
              'output' => { 'parameters' => {
                'description' => { 'type' => 'String', 'description' => 'omit prose' },
                'custom' => { 'type' => 'Custom', 'default' => { 'description' => 'real data' } },
                'password' => { 'type' => 'String', 'protected' => true, 'default' => 'secret' },
                'kind' => { 'type' => 'String', 'validators' => {
                  'include' => { 'values' => { 'description' => 'label' } }
                } }
              } }
            }
          }
        }
      }
    }
  end

  def snapshot
    described_class.build(description:, api_version: '7.0', protocol_version: '2.0')
  end

  it 'keeps field, choice and Custom data keys while removing prose and protected defaults' do
    action = snapshot.dig('description', 'resources', 'example', 'actions', 'show')
    expect(action).not_to have_key('description')
    expect(action).not_to have_key('examples')
    params = action.dig('output', 'parameters')
    expect(params.fetch('description')).to eq('type' => 'String')
    expect(params.dig('custom', 'default', 'description')).to eq('real data')
    expect(params.fetch('password')).not_to have_key('default')
    expect(params.dig('kind', 'validators', 'include', 'values')).to eq('description' => nil)
  end

  it 'emits exactly the agreed envelope keys with canonical bytes' do
    expect(snapshot.keys.sort).to eq(%w[api_version description mount_path profile protocol_version schema_format source_url])
    expect(snapshot.fetch('source_url')).to eq('https://schema.invalid/v7.0/')
    expect(described_class.canonical({ 'z' => [2, 1], 'a' => { 'b' => 1 } }))
      .to eq("{\n  \"a\": {\n    \"b\": 1\n  },\n  \"z\": [\n    2,\n    1\n  ]\n}\n")
  end

  it 'rejects wrong version or protocol rather than silently exporting a partial schema' do
    description['help'] = '/v6.0/'
    expect { snapshot }.to raise_error(VpsAdmin::SchemaExport::UnsafeInput, /requested API version/)
    expect { described_class.build(description:, api_version: '7.0', protocol_version: '3.0') }
      .to raise_error(VpsAdmin::SchemaExport::UnsafeInput, /protocol/)
  end

  it 'inventories nested declared resources without dropping their actions' do
    child = Marshal.load(Marshal.dump(description.fetch('resources').fetch('example')))
    child.fetch('actions').fetch('show')['scope'] = 'example.child#show'
    description.fetch('resources').fetch('example').fetch('resources')['child'] = child
    expect(described_class.inventory(snapshot.fetch('description')))
      .to include('resources' => 2, 'actions' => 2, 'parameters' => 8)
  end

  it 'rejects credential URLs and escaped path traversal without stripping real data' do
    ['https://user:secret@example.invalid/a', 'https://example.invalid/a?token=secret'].each do |url|
      description['authentication'] = { 'oauth2' => { 'token_url' => url } }
      expect { snapshot }.to raise_error(VpsAdmin::SchemaExport::UnsafeInput, /URL/)
    end
    description['authentication'] = {}
    description['help'] = '/v7.0/'
    description['resources']['example']['actions']['show']['path'] = '/v7.0/%2e%2e/private'
    expect { snapshot }.to raise_error(VpsAdmin::SchemaExport::UnsafeInput, /path/)
  end
end
