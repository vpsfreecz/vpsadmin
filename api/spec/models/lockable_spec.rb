# frozen_string_literal: true

RSpec.describe Lockable do
  let(:resource) do
    UserClusterResource.find_by!(
      user: SpecSeed.user,
      environment: SpecSeed.environment,
      cluster_resource: ClusterResource.find_by!(name: 'ipv4')
    )
  end

  around do |example|
    with_current_context do
      example.run
    end
  end

  it 'acquires a lock' do
    lock = resource.acquire_lock

    expect(lock).to be_a(ResourceLock)
    expect(resource.locked?).to be(true)
    expect(resource.get_current_lock).to eq(lock)
  end

  it 'raises ResourceLocked on duplicate acquisition' do
    first_lock = resource.acquire_lock

    expect do
      resource.acquire_lock
    end.to raise_error(ResourceLocked)

    first_lock.release
  end

  it 'eventually succeeds in block mode once the lock is released' do
    first_lock = resource.acquire_lock

    allow(resource).to receive(:sleep) do |_seconds|
      first_lock.release
      0
    end

    second_lock = resource.acquire_lock(block: true, timeout: 10)

    expect(resource).to have_received(:sleep).with(5)
    expect(second_lock).to be_a(ResourceLock)
    expect(resource.get_current_lock).to eq(second_lock)
  end

  it 'times out in block mode when the timeout has already expired' do
    first_lock = resource.acquire_lock

    expect do
      resource.acquire_lock(block: true, timeout: -1)
    end.to raise_error(ResourceLocked)

    first_lock.release
  end

  it 'releases a lock row' do
    lock = resource.acquire_lock
    resource.release_lock

    expect(ResourceLock.where(id: lock.id)).to be_empty
    expect(resource.locked?).to be(false)
  end
end
