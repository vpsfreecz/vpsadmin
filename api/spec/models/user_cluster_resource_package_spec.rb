# frozen_string_literal: true

require 'spec_helper'

RSpec.describe UserClusterResourcePackage do
  let(:environment) { SpecSeed.environment }
  let(:user) { SpecSeed.user }
  let(:cpu) { ensure_cluster_resource!(:cpu) }

  before do
    ensure_user_cluster_resources!(user: user, environment: environment)
  end

  def cpu_value
    UserClusterResource.find_by!(
      user: user,
      environment: environment,
      cluster_resource: cpu
    ).value
  end

  it 'recalculates user resources after destroy' do
    pkg = create_shared_package!(label: 'Spec UCRP Destroy', values: { cpu: 3 })
    user_pkg = assign_package!(package: pkg, user: user, environment: environment)

    expect(cpu_value).to eq(3)

    expect do
      user_pkg.destroy!
    end.to change { cpu_value }.from(3).to(0)
  end

  it 'delegates label to the cluster resource package' do
    pkg = create_shared_package!(label: 'Spec UCRP Label', values: { cpu: 1 })
    user_pkg = assign_package!(package: pkg, user: user, environment: environment)

    expect(user_pkg.label).to eq('Spec UCRP Label')
  end

  it 'delegates destroyability to the cluster resource package' do
    shared = create_shared_package!(label: 'Spec UCRP Shared', values: { cpu: 1 })
    personal = create_personal_package!(
      user: user,
      environment: environment,
      values: { cpu: 2 }
    )

    shared_assignment = assign_package!(
      package: shared,
      user: user,
      environment: environment
    )
    personal_assignment = personal.user_cluster_resource_packages.first

    expect(shared_assignment.can_destroy?).to be(true)
    expect(personal_assignment.can_destroy?).to be(false)
  end

  it 'delegates personal package type to the cluster resource package' do
    personal = create_personal_package!(
      user: user,
      environment: environment,
      values: { cpu: 2 }
    )

    expect(personal.user_cluster_resource_packages.first.is_personal).to be(true)
  end
end
