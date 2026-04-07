# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/vps/deploy_user_data'
require 'nodectld/vps_user_data'
require 'nodectld/vps_user_data/script'

RSpec.describe NodeCtld::Commands::Vps::DeployUserData do
  let(:driver) { build_vps_driver }
  let(:handler) { class_double(NodeCtld::VpsUserData::Script, deploy: nil) }
  let(:cmd) do
    described_class.new(
      driver,
      'vps_id' => 101,
      'format' => 'script',
      'content' => "#!/bin/sh\necho spec\n",
      'os_template' => { 'distribution' => 'specos', 'version' => '1' }
    )
  end

  before do
    allow(NodeCtld::VpsUserData).to receive(:for_format).with('script').and_return(handler)
  end

  it 'dispatches deployment to the format-specific handler' do
    expect(cmd.exec).to eq(ret: :ok)
    expect(handler).to have_received(:deploy).with(
      101,
      'script',
      "#!/bin/sh\necho spec\n",
      { 'distribution' => 'specos', 'version' => '1' }
    )
  end

  it 'has a no-op rollback' do
    expect(cmd.rollback).to eq(ret: :ok)
  end
end
