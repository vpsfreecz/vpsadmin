# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/ct_hook_installer'

RSpec.describe NodeCtld::CtHookInstaller do
  let(:tmpdir) { Dir.mktmpdir('ct-hook-installer-spec') }
  let(:pool_fs) { File.join(tmpdir, 'tank', 'ct').delete_prefix('/') }
  let(:hook_path) { File.join(tmpdir, 'tank', 'hook', 'ct', '101', 'veth-up') }

  after do
    FileUtils.rm_rf(tmpdir)
  end

  it 'creates the per-container hook directory before installing hooks' do
    FileUtils.mkdir_p(File.join(tmpdir, 'tank', 'ct'))

    described_class.new(pool_fs, 101).install_hooks(%w[veth-up])

    expect(File.file?(hook_path)).to be(true)
    expect(File.stat(hook_path).mode & 0o777).to eq(0o500)
  end
end
