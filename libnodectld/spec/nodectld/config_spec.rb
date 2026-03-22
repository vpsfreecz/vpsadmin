# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/config'

RSpec.describe NodeCtld::AppConfig do
  let(:cfg) { described_class.new('/tmp/nodectld-config-spec.yml') }

  before do
    cfg.instance_variable_set(:@cfg, Marshal.load(Marshal.dump(NodeCtld::IMPLICIT_CONFIG)))
  end

  it 'symbolizes nested keys when patching runtime config' do
    cfg.patch(
      'mbuffer' => {
        'send' => {
          'command' => '/run/test/faulty-mbuffer'
        }
      }
    )

    expect(cfg.get(:mbuffer, :send, :command)).to eq('/run/test/faulty-mbuffer')
  end
end
