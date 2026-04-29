# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ClusterResourcePackage do
  let(:environment) { SpecSeed.environment }
  let(:cpu) { ensure_cluster_resource!(:cpu) }
  let(:memory) { ensure_cluster_resource!(:memory) }

  before do
    ensure_user_cluster_resources!(user: user, environment: environment)
    ensure_user_cluster_resources!(user: other_user, environment: environment)
  end

  def admin
    SpecSeed.admin
  end

  def user
    SpecSeed.user
  end

  def other_user
    SpecSeed.other_user
  end

  def resource_value(resource, owner = user)
    UserClusterResource.find_by!(
      user: owner,
      environment: environment,
      cluster_resource: resource
    ).value
  end

  def package_item(package, resource)
    ClusterResourcePackageItem.find_by!(
      cluster_resource_package: package,
      cluster_resource: resource
    )
  end

  it 'recalculates assigned user resources when adding an item' do
    pkg = create_shared_package!(label: 'Spec Shared Add', values: {})

    UserClusterResourcePackage.create!(
      cluster_resource_package: pkg,
      user: user,
      environment: environment,
      added_by: admin,
      comment: 'spec'
    )

    expect do
      pkg.add_item(cpu, 4)
    end.to change { resource_value(cpu) }.from(0).to(4)
  end

  it 'recalculates assigned user resources when updating an item' do
    pkg = create_shared_package!(label: 'Spec Shared Update', values: { cpu: 2 })
    assign_package!(package: pkg, user: user, environment: environment)

    expect do
      pkg.update_item(package_item(pkg, cpu), 5)
    end.to change { resource_value(cpu) }.from(2).to(5)
  end

  it 'recalculates assigned user resources when removing an item' do
    pkg = create_shared_package!(label: 'Spec Shared Remove', values: { cpu: 2 })
    assign_package!(package: pkg, user: user, environment: environment)

    expect do
      pkg.remove_item(package_item(pkg, cpu))
    end.to change { resource_value(cpu) }.from(2).to(0)
  end

  it 'assigns a shared package and increases effective user resources' do
    pkg = create_shared_package!(
      label: 'Spec Shared Assign',
      values: { cpu: 4, memory: 1024 }
    )

    expect do
      assign_package!(package: pkg, user: user, environment: environment)
    end.to change(UserClusterResourcePackage, :count).by(1)

    expect(resource_value(cpu)).to eq(4)
    expect(resource_value(memory)).to eq(1024)
  end

  it 'assigns from a personal package and keeps overall resource totals stable' do
    personal = create_personal_package!(
      user: user,
      environment: environment,
      values: { cpu: 10, memory: 2048 }
    )
    pkg = create_shared_package!(
      label: 'Spec Shared From Personal',
      values: { cpu: 4, memory: 512 }
    )

    expect do
      assign_package!(
        package: pkg,
        user: user,
        environment: environment,
        from_personal: true
      )
    end.to change(UserClusterResourcePackage, :count).by(1)

    expect(package_item(personal, cpu).reload.value).to eq(6)
    expect(package_item(personal, memory).reload.value).to eq(1536)
    expect(resource_value(cpu)).to eq(10)
    expect(resource_value(memory)).to eq(2048)
  end

  it 'raises when assigning from personal and a personal item is missing' do
    create_personal_package!(
      user: user,
      environment: environment,
      values: { memory: 2048 }
    )
    pkg = create_shared_package!(
      label: 'Spec Shared Missing Personal',
      values: { cpu: 4 }
    )

    expect do
      assign_package!(
        package: pkg,
        user: user,
        environment: environment,
        from_personal: true
      )
    end.to raise_error(
      VpsAdmin::API::Exceptions::UserResourceAllocationError,
      /resource cpu not found/
    )
  end

  it 'raises when assigning from personal and the personal item is too small' do
    create_personal_package!(
      user: user,
      environment: environment,
      values: { cpu: 2 }
    )
    pkg = create_shared_package!(
      label: 'Spec Shared Too Much',
      values: { cpu: 4 }
    )

    expect do
      assign_package!(
        package: pkg,
        user: user,
        environment: environment,
        from_personal: true
      )
    end.to raise_error(
      VpsAdmin::API::Exceptions::UserResourceAllocationError,
      /not enough cpu/
    )
  end

  it 'skips hard-deleted users during recalculation' do
    pkg = create_shared_package!(label: 'Spec Shared Deleted', values: {})
    deleted_user = other_user

    UserClusterResourcePackage.create!(
      cluster_resource_package: pkg,
      user: user,
      environment: environment,
      added_by: admin,
      comment: 'active'
    )
    UserClusterResourcePackage.create!(
      cluster_resource_package: pkg,
      user: deleted_user,
      environment: environment,
      added_by: admin,
      comment: 'deleted'
    )
    deleted_user.update!(object_state: :hard_delete)

    expect do
      pkg.add_item(cpu, 3)
    end.to change { resource_value(cpu) }.from(0).to(3)
  end

  it 'reports destroyability and personal package type' do
    shared = create_shared_package!(label: 'Spec Shared Type', values: {})
    personal = create_personal_package!(
      user: user,
      environment: environment,
      values: { cpu: 1 }
    )

    expect(shared.can_destroy?).to be(true)
    expect(shared.is_personal).to be(false)
    expect(personal.can_destroy?).to be(false)
    expect(personal.is_personal).to be(true)
  end
end
