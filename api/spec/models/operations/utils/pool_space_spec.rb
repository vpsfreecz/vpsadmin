# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'

RSpec.describe VpsAdmin::API::Operations::Utils::PoolSpace do
  let(:environment) { SpecSeed.environment }

  it 'falls back to requested diskspace for the root dataset without explicit refquota' do
    template = create_os_template!(
      datasets: [
        { 'name' => '/' }
      ]
    )

    expect(
      described_class.required_new_vps_diskspace!(
        os_template: template,
        diskspace: 4_096
      )
    ).to eq(4_096)
  end

  it 'supports integer and percentage refquota values' do
    template = create_os_template!(
      datasets: [
        { 'name' => '/', 'properties' => { 'refquota' => 4_096 } },
        { 'name' => '/var', 'properties' => { 'refquota' => '25%' } }
      ]
    )

    expect(
      described_class.template_refquota!(
        os_template: template,
        diskspace: 8_192,
        lookup_name: '/'
      )
    ).to eq(4_096)
    expect(
      described_class.template_refquota!(
        os_template: template,
        diskspace: 8_192,
        lookup_name: '/var'
      )
    ).to eq(2_048)
  end

  it 'includes template subdatasets in the total required size' do
    template = create_os_template!(
      datasets: [
        { 'name' => '/' },
        { 'name' => '/var', 'properties' => { 'refquota' => '25%' } },
        { 'name' => '/home', 'properties' => { 'refquota' => 512 } }
      ]
    )

    expect(
      described_class.required_new_vps_diskspace!(
        os_template: template,
        diskspace: 4_096
      )
    ).to eq(5_632)
  end

  it 'raises when a non-root dataset is missing refquota' do
    template = create_os_template!(
      datasets: [
        { 'name' => '/' },
        { 'name' => '/var' }
      ]
    )

    expect do
      described_class.required_new_vps_diskspace!(
        os_template: template,
        diskspace: 4_096
      )
    end.to raise_error(
      VpsAdmin::API::Exceptions::OperationError,
      %r{missing refquota option for dataset /var}
    )
  end

  it 'raises on invalid refquota format' do
    template = create_os_template!(
      datasets: [
        { 'name' => '/', 'properties' => { 'refquota' => 'oops' } }
      ]
    )

    expect do
      described_class.required_new_vps_diskspace!(
        os_template: template,
        diskspace: 4_096
      )
    end.to raise_error(
      VpsAdmin::API::Exceptions::OperationError,
      /unknown refquota format/
    )
  end

  it 'sums diskspace of the root dataset tree on one pool' do
    pool = create_pool!(node: SpecSeed.node, role: :hypervisor)
    _root_ds, root_dip = create_dataset_with_pool!(
      user: SpecSeed.user,
      pool: pool,
      name: "root-#{SecureRandom.hex(3)}"
    )
    _sub_ds, sub_dip = create_dataset_with_pool!(
      user: SpecSeed.user,
      pool: pool,
      parent: root_dip.dataset,
      name: "sub-#{SecureRandom.hex(3)}"
    )
    _sub2_ds, sub2_dip = create_dataset_with_pool!(
      user: SpecSeed.user,
      pool: pool,
      parent: sub_dip.dataset,
      name: "sub2-#{SecureRandom.hex(3)}"
    )

    allocate_diskspace!(root_dip, 4_096)
    allocate_diskspace!(sub_dip, 1_024)
    allocate_diskspace!(sub2_dip, 256)

    expect(described_class.required_dataset_tree_diskspace(root_dip)).to eq(5_376)
  end

  private

  def create_os_template!(datasets:)
    suffix = SecureRandom.hex(4)

    OsTemplate.create!(
      os_family: SpecSeed.os_family,
      label: "Pool Space #{suffix}",
      distribution: 'specos',
      version: '1',
      arch: 'x86_64',
      vendor: 'spec',
      variant: 'base',
      hypervisor_type: :vpsadminos,
      config: {
        'datasets' => datasets
      }
    )
  end

  def ensure_diskspace_resource!(user)
    resource = ClusterResource.find_by!(name: 'diskspace')

    UserClusterResource.find_or_create_by!(
      user: user,
      environment: environment,
      cluster_resource: resource
    ) do |ucr|
      ucr.value = 100_000
    end
  end

  def allocate_diskspace!(dip, value)
    ensure_diskspace_resource!(dip.dataset.user)

    prev = User.current
    User.current = SpecSeed.admin
    dip.allocate_resource!(
      :diskspace,
      value,
      user: dip.dataset.user,
      confirmed: ClusterResourceUse.confirmed(:confirmed),
      admin_override: true
    )
  ensure
    User.current = prev
  end
end
