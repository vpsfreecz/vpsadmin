# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/dataset'
require 'nodectld/commands/base'
require 'nodectld/commands/dataset/destroy'

RSpec.describe NodeCtld::Commands::Dataset::Destroy do
  let(:driver) { build_storage_driver }

  it 'destroys the dataset through NodeCtld::Dataset with trash semantics' do
    dataset = instance_double(NodeCtld::Dataset, destroy: true)
    allow(NodeCtld::Dataset).to receive(:new).and_return(dataset)

    cmd = described_class.new(
      driver,
      'pool_fs' => 'tank/backup',
      'name' => '101'
    )

    expect(cmd.exec).to eq(ret: :ok)
    expect(dataset).to have_received(:destroy).with(
      'tank/backup',
      '101',
      recursive: false,
      trash: true
    )
  end
end
