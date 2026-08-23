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

  it 'persists and recognizes a same-boot restart barrier' do
    described_class.persist(
      reason: 'spec',
      path:,
      boot_id_path:
    )

    expect(described_class.active?(
             path:,
             boot_id_path:
           )).to be(true)
    expect(JSON.parse(File.read(path))).to include(
      'reason' => 'spec'
    )
  end

  it 'ignores a barrier from another boot' do
    described_class.persist(
      reason: 'spec',
      path:,
      boot_id_path:
    )
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
    described_class.persist(
      reason: described_class::LEGACY_UPGRADE_REASON,
      path:,
      boot_id_path:
    )

    expect(described_class.coordinator_resume?(
             path:,
             boot_id_path:
           )).to be(true)
  end

  it 'does not defer an ordinary daemon restart resume' do
    described_class.persist(
      reason: 'osctld-restart',
      path:,
      boot_id_path:
    )

    expect(described_class.coordinator_resume?(
             path:,
             boot_id_path:
           )).to be(false)
  end

  it 'defers an unknown current-boot reason instead of clearing it' do
    described_class.persist(
      reason: 'new-coordinator',
      path:,
      boot_id_path:
    )

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

  it 'clears the barrier explicitly' do
    described_class.persist(
      reason: 'spec',
      path:,
      boot_id_path:
    )

    described_class.clear(path:)

    expect(File.exist?(path)).to be(false)
  end
end
