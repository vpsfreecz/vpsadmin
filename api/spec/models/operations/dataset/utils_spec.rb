# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::Dataset::Utils do
  subject(:helper) do
    Class.new do
      include VpsAdmin::API::Operations::Dataset::Utils
    end.new
  end

  def dataset_path(*new_record_values)
    new_record_values.map do |value|
      instance_double(Dataset, new_record?: value)
    end
  end

  it 'requires refquota when the pool enforces it' do
    dip = instance_double(DatasetInPool, pool: instance_double(Pool, refquota_check: true))

    expect do
      helper.check_refquota(dip, dataset_path(true), nil)
    end.to raise_error(VpsAdmin::API::Exceptions::PropertyInvalid, 'refquota must be set')
  end

  it 'allows a single new dataset under refquota enforcement' do
    dip = instance_double(DatasetInPool, pool: instance_double(Pool, refquota_check: true))

    expect do
      helper.check_refquota(dip, dataset_path(false, true), 1024)
    end.not_to raise_error
  end

  it 'rejects more than one new nested dataset under refquota enforcement' do
    dip = instance_double(DatasetInPool, pool: instance_double(Pool, refquota_check: true))

    expect do
      helper.check_refquota(dip, dataset_path(true, true), 1024)
    end.to raise_error(
      VpsAdmin::API::Exceptions::DatasetNestingForbidden,
      'Cannot create more than one dataset at a time'
    )
  end

  it 'does nothing when the pool does not enforce refquota' do
    dip = instance_double(DatasetInPool, pool: instance_double(Pool, refquota_check: false))

    expect do
      helper.check_refquota(dip, dataset_path(true, true), nil)
    end.not_to raise_error
  end
end
