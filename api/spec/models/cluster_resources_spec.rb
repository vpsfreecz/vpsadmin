# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::ClusterResources do
  around { |example| with_current_context(user: SpecSeed.user) { example.run } }

  %i[cpu memory swap diskspace ipv4 ipv4_private ipv6].each do |name|
    context "with #{name}" do
      let(:resource) { ClusterResource.find_by!(name:) }
      let(:fixture) { create_netif_vps_fixture! }
      let(:owner) do
        if name.to_s.start_with?('ipv')
          SpecSeed.user.environment_user_configs.find_by!(environment: SpecSeed.environment)
        elsif name == :diskspace
          fixture[:dataset_in_pool]
        else
          fixture[:vps]
        end
      end
      let(:budget) do
        UserClusterResource.find_or_initialize_by(
          user: SpecSeed.user, environment: SpecSeed.environment, cluster_resource: resource
        ).tap { |r| r.update!(value: 100) }
      end
      let(:use) do
        budget
        owner.allocate_resource!(name, 20, user: SpecSeed.user, confirmed: ClusterResourceUse.confirmed(:confirmed))
      end

      before { resource.update!(min: 0, max: 100, stepsize: 2) }

      it 'preserves absolute update persistence and return values', :absolute do
        original = use
        proposed = owner.reallocate_resource!(name, 24, user: SpecSeed.user)
        expect(proposed).to be_a(ClusterResourceUse)
        expect(proposed.value).to eq(24)
        expect(original.reload.value).to eq(20)
        expect(owner.reallocate_resource!(name, 26, user: SpecSeed.user, save: true)).to be(true)
        expect(original.reload.value).to eq(26)
      end

      it 'preserves first-use creation and confirmation state', :absolute do
        budget
        row = owner.reallocate_resource!(name, 20, user: SpecSeed.user)
        expect(row).to be_persisted
        expect(row.confirmed).to eq(:confirm_create)
        expect(owner.get_cluster_resources([name]).pluck(:id)).to eq([row.id])
      end

      it 'preserves limits, overrides and step validation', :absolute do
        original = use
        expect { owner.reallocate_resource!(name, 102, user: SpecSeed.user) }
          .to raise_error(VpsAdmin::API::Exceptions::ClusterResourceAllocationError)
        expect(owner.reallocate_resource!(name, 102, user: SpecSeed.user, override: true).value).to eq(102)
        expect { owner.reallocate_resource!(name, 23, user: SpecSeed.user, override: true) }
          .to raise_error(VpsAdmin::API::Exceptions::ClusterResourceAllocationError)
        expect(original.reload.value).to eq(20)
      end

      it 'preserves administrative limits until explicitly overridden', :absolute do
        original = use
        with_current_context(user: SpecSeed.admin) do
          owner.reallocate_resource!(name, 20, user: SpecSeed.user, save: true, lock_type: :not_more)
        end
        expect { owner.reallocate_resource!(name, 22, user: SpecSeed.user) }
          .to raise_error(VpsAdmin::API::Exceptions::ClusterResourceAllocationError)
        expect(original.reload.admin_lock_type).to eq('not_more')
        expect(original.admin_limit).to eq(20)
        with_current_context(user: SpecSeed.admin) do
          owner.reallocate_resource!(name, 22, user: SpecSeed.user, save: true, lock_type: :no_lock)
        end
        expect(original.reload.admin_limit).to be_nil
      end

      it 'applies positive, negative and zero relative changes without leaking locks' do
        original = use
        [4, -2, 0].each do |delta|
          changed = owner.adjust_resource!(name, delta:, user: SpecSeed.user, save: true)
          expect(changed).to be_a(ClusterResourceUse)
        end
        expect(original.reload.value).to eq(22)
        expect(budget).not_to be_locked
      end

      it 'uses the shared validation for relative changes and leaves failures atomic' do
        original = use
        [82, -22, 1].each do |delta|
          expect { owner.adjust_resource!(name, delta:, user: SpecSeed.user, save: true) }
            .to raise_error(ActiveRecord::RecordInvalid)
          expect(original.reload.value).to eq(20)
          expect(budget).not_to be_locked
        end
        expect(owner.adjust_resource!(name, delta: 82, user: SpecSeed.user, save: true, override: true).value).to eq(102)
      end

      it 'retains deferred usage and quota reservation until confirmation' do
        original = use
        chain = build_transaction_chain!
        proposed = owner.adjust_resource!(name, delta: 4, user: SpecSeed.user, chain:)
        expect(proposed.value).to eq(24)
        expect(original.reload.value).to eq(20)
        expect(budget.get_current_lock.locked_by).to eq(chain)
        expect { owner.adjust_resource!(name, delta: 2, user: SpecSeed.user, save: true) }
          .to raise_error(ResourceLocked)
      end

      it 'creates a missing deferred use through the existing allocation path' do
        budget
        chain = build_transaction_chain!
        row = owner.adjust_resource!(name, delta: 20, user: SpecSeed.user, chain:)
        expect(row).to be_persisted
        expect(row.value).to eq(20)
        expect(row.confirmed).to eq(:confirm_create)
        expect(budget.get_current_lock.locked_by).to eq(chain)
      end

      it 'rejects a relative proposal with no persistence or chain' do
        expect { owner.adjust_resource!(name, delta: 2, user: SpecSeed.user) }
          .to raise_error(ArgumentError, /save: true or a chain/)
      end

      it 'preserves missing user resource errors' do
        owner
        budget.destroy!
        expect { owner.reallocate_resource!(name, 20, user: SpecSeed.user) }
          .to raise_error(VpsAdmin::API::Exceptions::UserResourceMissing)
        expect { owner.adjust_resource!(name, delta: 20, user: SpecSeed.user, save: true) }
          .to raise_error(VpsAdmin::API::Exceptions::UserResourceMissing)
      end

      it 'preserves generic resource free and transfer behavior', :absolute do
        original = use
        target = UserClusterResource.find_or_initialize_by(
          user: SpecSeed.other_user, environment: SpecSeed.environment, cluster_resource: resource
        )
        target.update!(value: 100)
        changes = owner.transfer_resources!(SpecSeed.other_user)
        expect(changes.values).to include(user_cluster_resource_id: target.id)
        expect(original.reload.user_cluster_resource_id).to eq(budget.id)
        owner.free_resource!(name, free_object: false)
        expect(original.reload.confirmed).to eq(:confirm_destroy)
      end
    end
  end

  it 'keeps unrelated pending owner attributes in both update modes' do
    fixture = create_netif_vps_fixture!
    vps = fixture[:vps]
    ensure_numeric_resources!(user: SpecSeed.user, environment: SpecSeed.environment)
    use = vps.allocate_resource!(:cpu, 2, user: SpecSeed.user, confirmed: ClusterResourceUse.confirmed(:confirmed))
    vps.info = 'pending change'
    vps.reallocate_resource!(:cpu, 3, user: SpecSeed.user)
    expect(vps.info).to eq('pending change')
    vps.adjust_resource!(:cpu, delta: 1, user: SpecSeed.user, save: true)
    expect(vps.info).to eq('pending change')
    expect(vps).to be_info_changed
    expect(use.reload.value).to eq(3)
  end
end
