# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/vps/os_template'

RSpec.describe NodeCtld::Commands::Vps::OsTemplate do
  let(:driver) { build_vps_driver }
  let(:cmd) do
    described_class.new(
      driver,
      'vps_id' => 101,
      'new' => {
        'distribution' => 'specos',
        'version' => '1',
        'arch' => 'x86_64',
        'vendor' => 'spec',
        'variant' => 'base'
      },
      'original' => {
        'distribution' => 'oldos',
        'version' => '0',
        'arch' => 'x86_64',
        'vendor' => 'legacy',
        'variant' => 'minimal'
      }
    )
  end

  before do
    allow(cmd).to receive(:osctl).and_return(ret: :ok)
  end

  it 'sets the requested distribution tuple on exec' do
    expect(cmd.exec).to eq(ret: :ok)
    expect(cmd).to have_received(:osctl).with(
      %i[ct set distribution],
      [101, 'specos', '1', 'x86_64', 'spec', 'base']
    )
  end

  it 'restores the original distribution tuple on rollback' do
    expect(cmd.rollback).to eq(ret: :ok)
    expect(cmd).to have_received(:osctl).with(
      %i[ct set distribution],
      [101, 'oldos', '0', 'x86_64', 'legacy', 'minimal']
    )
  end
end
