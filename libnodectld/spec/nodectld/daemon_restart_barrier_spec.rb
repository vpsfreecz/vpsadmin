# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/daemon_restart_barrier'

RSpec.describe NodeCtld::DaemonRestartBarrier do
  let(:root) { Dir.mktmpdir('nodectld-restart-barrier') }
  let(:path) { File.join(root, 'pause.json') }
  let(:boot_id_path) { File.join(root, 'boot-id') }

  before do
    File.write(boot_id_path, "boot-1\n")
  end

  after { FileUtils.rm_rf(root) }

  def write_marker(reason:, boot_id: 'boot-1', schema: 1)
    File.write(
      path,
      JSON.generate('schema' => schema, 'boot_id' => boot_id, 'reason' => reason)
    )
  end

  it 'acquires and recognizes a same-boot ordinary restart barrier' do
    expect(described_class.acquire_ordinary(
             path:,
             boot_id_path:
           )).to be(true)

    expect(described_class.active?(
             path:,
             boot_id_path:
           )).to be(true)
    expect(JSON.parse(File.read(path))).to include(
      'reason' => described_class::ORDINARY_RESTART_REASON
    )
  end

  it 'ignores a barrier from another boot' do
    write_marker(reason: 'spec')
    File.write(boot_id_path, "boot-2\n")

    expect(described_class.active?(
             path:,
             boot_id_path:
           )).to be(false)
  end

  it 'keeps admission closed for a malformed barrier' do
    File.write(path, '{')

    expect(described_class.active?(
             path:,
             boot_id_path:
           )).to be(true)
  end

  it 'keeps admission closed for an unsupported barrier schema' do
    File.write(
      path,
      JSON.generate('schema' => 2, 'boot_id' => 'boot-1')
    )

    expect(described_class.active?(
             path:,
             boot_id_path:
           )).to be(true)
  end

  it 'ignores an unsupported barrier from another boot' do
    File.write(
      path,
      JSON.generate('schema' => 2, 'boot_id' => 'boot-0')
    )

    expect(described_class.active?(
             path:,
             boot_id_path:
           )).to be(false)
    expect(described_class.coordinator_resume?(
             path:,
             boot_id_path:
           )).to be(false)
  end

  it 'defers a current-boot legacy upgrade resume to its coordinator' do
    write_marker(reason: described_class::LEGACY_UPGRADE_REASON)

    expect(described_class.coordinator_resume?(
             path:,
             boot_id_path:
           )).to be(true)
  end

  it 'does not defer an ordinary daemon restart resume' do
    write_marker(reason: described_class::ORDINARY_RESTART_REASON)

    expect(described_class.coordinator_resume?(
             path:,
             boot_id_path:
           )).to be(false)
  end

  it 'defers an unknown current-boot reason instead of clearing it' do
    write_marker(reason: 'new-coordinator')

    expect(described_class.coordinator_resume?(
             path:,
             boot_id_path:
           )).to be(true)
  end

  it 'defers malformed state instead of clearing it fail-open' do
    File.write(path, '{')

    expect(described_class.coordinator_resume?(
             path:,
             boot_id_path:
           )).to be(true)
  end

  it 'preserves a same-boot legacy barrier during ordinary acquisition' do
    write_marker(reason: described_class::LEGACY_UPGRADE_REASON)
    before = File.read(path)

    expect(described_class.acquire_ordinary(
             path:,
             boot_id_path:
           )).to be(false)
    expect(File.read(path)).to eq(before)
  end

  it 'preserves an unknown same-boot barrier during ordinary acquisition' do
    write_marker(reason: 'future-coordinator')
    before = File.read(path)

    expect(described_class.acquire_ordinary(
             path:,
             boot_id_path:
           )).to be(false)
    expect(File.read(path)).to eq(before)
  end

  it 'preserves a malformed barrier during ordinary acquisition' do
    File.write(path, '{')

    expect(described_class.acquire_ordinary(
             path:,
             boot_id_path:
           )).to be(false)
    expect(File.read(path)).to eq('{')
  end

  it 'preserves a non-object barrier during ordinary acquisition' do
    File.write(path, 'null')

    expect(described_class.acquire_ordinary(
             path:,
             boot_id_path:
           )).to be(false)
    expect(File.read(path)).to eq('null')
  end

  it 'replaces a stale barrier when acquiring ordinary ownership' do
    write_marker(reason: 'old-coordinator', boot_id: 'boot-0')

    expect(described_class.acquire_ordinary(
             path:,
             boot_id_path:
           )).to be(true)
    expect(JSON.parse(File.read(path))).to include(
      'boot_id' => 'boot-1',
      'reason' => described_class::ORDINARY_RESTART_REASON
    )
  end

  it 'releases an ordinary restart barrier' do
    write_marker(reason: described_class::ORDINARY_RESTART_REASON)

    expect(described_class.release_ordinary(
             path:,
             boot_id_path:
           )).to eq(:released)

    expect(File.exist?(path)).to be(false)
  end

  it 'does not release a coordinator-owned barrier' do
    write_marker(reason: described_class::LEGACY_UPGRADE_REASON)

    expect(described_class.release_ordinary(
             path:,
             boot_id_path:
           )).to eq(:deferred)

    expect(JSON.parse(File.read(path))).to include(
      'reason' => described_class::LEGACY_UPGRADE_REASON
    )
  end

  it 'does not release a non-object barrier' do
    File.write(path, 'false')

    expect(described_class.release_ordinary(
             path:,
             boot_id_path:
           )).to eq(:deferred)
    expect(File.read(path)).to eq('false')
  end

  it 'reports an absent ordinary barrier without creating it' do
    expect(described_class.release_ordinary(
             path:,
             boot_id_path:
           )).to eq(:absent)

    expect(File.exist?(path)).to be(false)
  end
end
