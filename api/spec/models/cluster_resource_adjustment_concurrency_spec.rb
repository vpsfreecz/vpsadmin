# frozen_string_literal: true

require 'spec_helper'
require 'timeout'

RSpec.describe VpsAdmin::API::ClusterResources, :no_transaction do
  let(:ids) { {} }

  def connection_thread(&block)
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        with_current_context(user: SpecSeed.user) do |session|
          block.call
        ensure
          session.destroy!
        end
      end
    end
  end

  before do
    connection_thread do
      resource = ClusterResource.create!(
        name: "counter_#{SecureRandom.hex(5)}", label: 'Counter',
        min: 0, max: 100, stepsize: 1, resource_type: :numeric
      )
      budget = UserClusterResource.create!(
        user: SpecSeed.user, environment: SpecSeed.environment, cluster_resource: resource, value: 100
      )
      owner = SpecSeed.user.environment_user_configs.find_by!(environment: SpecSeed.environment)
      use = owner.allocate_resource!(resource.name, 20, user: SpecSeed.user,
                                                        confirmed: ClusterResourceUse.confirmed(:confirmed))
      ids.merge!(resource: resource.id, name: resource.name, budget: budget.id, owner: owner.id, use: use.id)
    end.value
  end

  after do
    connection_thread do
      ClusterResourceUse.where(user_cluster_resource_id: ids[:budget]).delete_all
      ResourceLock.where(resource: 'UserClusterResource', row_id: ids[:budget]).delete_all
      UserClusterResource.where(id: ids[:budget]).delete_all
      ClusterResource.where(id: ids[:resource]).delete_all
      PaperTrail::Version.where(item_type: 'UserClusterResource', item_id: ids[:budget]).delete_all
    end.value
  end

  def after_old_snapshot(change:)
    ready = Queue.new
    resume = Queue.new
    worker = connection_thread do
      EnvironmentUserConfig.transaction do
        ClusterResourceUse.where(user_cluster_resource_id: ids[:budget]).sum(:value)
        UserClusterResource.find(ids[:budget]).value
        ready << true
        resume.pop
        yield EnvironmentUserConfig.find(ids[:owner])
      end
    end
    Timeout.timeout(10) { ready.pop }
    connection_thread(&change).value
    resume << true
    Timeout.timeout(20) { worker.value }
  ensure
    resume << true if resume
    worker&.join(25) || worker&.kill&.join
  end

  it 'adds to the current value after another transaction changed the usage' do
    after_old_snapshot(change: lambda {
      EnvironmentUserConfig.find(ids[:owner]).adjust_resource!(ids[:name], delta: 2, user: SpecSeed.user, save: true)
    }) do |owner|
      expect(owner.adjust_resource!(ids[:name], delta: 4, user: SpecSeed.user, save: true).value).to eq(26)
    end
    expect(ClusterResourceUse.find(ids[:use]).value).to eq(26)
  end

  it 'includes another object newly consuming the same budget during validation' do
    after_old_snapshot(change: lambda {
      other_owner = SpecSeed.other_user.environment_user_configs.find_by!(environment: SpecSeed.environment)
      other_owner.allocate_resource!(ids[:name], 78, user: SpecSeed.user,
                                                     confirmed: ClusterResourceUse.confirmed(:confirmed))
    }) do |owner|
      expect { owner.adjust_resource!(ids[:name], delta: 4, user: SpecSeed.user, save: true) }
        .to raise_error(ActiveRecord::RecordInvalid)
    end
    expect(ClusterResourceUse.find(ids[:use]).value).to eq(20)
  end

  it 'validates against the current budget after its allowance is reduced' do
    after_old_snapshot(change: -> { UserClusterResource.find(ids[:budget]).update!(value: 22) }) do |owner|
      expect { owner.adjust_resource!(ids[:name], delta: 4, user: SpecSeed.user, save: true) }
        .to raise_error(ActiveRecord::RecordInvalid)
    end
    expect(ClusterResourceUse.find(ids[:use]).value).to eq(20)
  end

  it 'serializes first-use creation without duplicate accounting rows' do
    ClusterResourceUse.find(ids[:use]).destroy!
    ready = Queue.new
    resume = Queue.new
    workers = Array.new(2) do
      connection_thread do
        EnvironmentUserConfig.transaction do
          ClusterResourceUse.where(user_cluster_resource_id: ids[:budget]).count
          ready << true
          resume.pop
          EnvironmentUserConfig.find(ids[:owner]).adjust_resource!(ids[:name], delta: 2,
                                                                               user: SpecSeed.user, save: true)
        end
      end
    end
    2.times { Timeout.timeout(10) { ready.pop } }
    2.times { resume << true }
    Timeout.timeout(20) { workers.each(&:value) }
    expect(ClusterResourceUse.where(user_cluster_resource_id: ids[:budget]).pluck(:value)).to eq([4])
  ensure
    2.times { resume << true } if resume
    workers&.each { |thread| thread.join(25) || thread.kill.join }
  end
end
