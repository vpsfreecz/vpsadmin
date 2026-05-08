# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::CLI::Commands::BaseDownload do
  def command_with(api)
    described_class.allocate.tap do |command|
      command.instance_variable_set(:@api, api)
    end
  end

  it 'reuses an existing download with matching snapshot, base, and format' do
    existing = FakeRecord.new(
      id: 10,
      from_snapshot: true,
      from_snapshot_id: 3,
      format: 'incremental_stream'
    )
    collection = FakeCollection.new([existing])
    api = FakeRecord.new(snapshot_download: collection)

    download, created = command_with(api).send(
      :find_or_create_dl,
      { snapshot: 5, from_snapshot: 3, format: :incremental_stream }
    )

    expect(download).to eq(existing)
    expect(created).to be(false)
    expect(collection.created).to be_empty
  end

  it 'raises when the reusable download has a different format' do
    existing = FakeRecord.new(id: 11, from_snapshot: nil, format: 'archive')
    api = FakeRecord.new(snapshot_download: FakeCollection.new([existing]))

    expect do
      command_with(api).send(
        :find_or_create_dl,
        { snapshot: 5, from_snapshot: nil, format: :stream }
      )
    end.to raise_error(RuntimeError, /unusable format 'archive'/)
  end

  it 'creates a download when none can be reused' do
    collection = FakeCollection.new
    api = FakeRecord.new(snapshot_download: collection)
    opts = { snapshot: 5, from_snapshot: nil, format: :archive }

    download, created = command_with(api).send(:find_or_create_dl, opts)

    expect(download.snapshot).to eq(5)
    expect(created).to be(true)
    expect(collection.created).to eq([opts])
  end
end
