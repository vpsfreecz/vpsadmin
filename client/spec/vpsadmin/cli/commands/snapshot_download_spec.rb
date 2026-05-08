# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::CLI::Commands::SnapshotDownload do
  def command_with(api: FakeRecord.new, opts: {})
    described_class.allocate.tap do |command|
      command.instance_variable_set(:@api, api)
      command.instance_variable_set(:@opts, opts)
    end
  end

  it 'opens existing files for resume from their current size' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'download.dat')
      File.write(path, 'partial')
      command = command_with(opts: { resume: true })

      file, action, position = command.send(:open_file, path)
      file.close

      expect(action).to eq(:resume)
      expect(position).to eq(7)
    end
  end

  it 'truncates existing files when force is enabled' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'download.dat')
      File.write(path, 'old')
      command = command_with(opts: { force: true })

      file, action, position = command.send(:open_file, path)
      file.write('new')
      file.close

      expect(action).to eq(:overwrite)
      expect(position).to eq(0)
      expect(File.read(path)).to eq('new')
    end
  end

  it 'downloads to the selected file and deletes the server-side download' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'download.dat')
      collection = FakeCollection.new
      api = FakeRecord.new(snapshot_download: collection)
      command = command_with(api: api)

      allow(command).to receive(:sleep)
      allow(VpsAdmin::CLI::StreamDownloader).to receive(:download)

      command.do_exec(
        snapshot: 5,
        format: 'archive',
        file: path,
        quiet: true,
        checksum: true,
        delete_after: true
      )

      expect(VpsAdmin::CLI::StreamDownloader).to have_received(:download)
        .with(
          api,
          an_object_having_attributes(id: 1),
          an_instance_of(File),
          progress: false,
          position: 0,
          max_rate: nil,
          checksum: true
        )
      expect(collection.deleted).to eq([1])
    end
  end
end
