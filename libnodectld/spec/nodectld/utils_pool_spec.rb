# frozen_string_literal: true

class PoolUtilsSpecHost
  include NodeCtld::Utils::Pool
end

RSpec.describe NodeCtld::Utils::Pool do
  let(:host) { PoolUtilsSpecHost.new }
  let(:pool_id) { 123 }

  it 'writes the download healthcheck file into the pool download dataset root' do
    Dir.mktmpdir do |tmpdir|
      pool_fs = File.join(tmpdir.delete_prefix('/'), 'tank')
      FileUtils.mkdir_p(host.pool_download_dir(pool_fs))

      path = host.ensure_pool_download_healthcheck(pool_fs, pool_id)

      expect(path).to eq(
        File.join(host.pool_download_dir(pool_fs), described_class::DOWNLOAD_HEALTHCHECK_FILE)
      )
      expect(File.read(path)).to eq(host.pool_download_healthcheck_content(pool_id))
    end
  end
end
