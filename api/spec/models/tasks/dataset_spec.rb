# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Tasks::Dataset do
  let(:task) { described_class.new }

  it 'prunes only dataset property logs older than the configured number of days' do
    stub_const("#{described_class}::DAYS", 1)
    fixture = build_standalone_vps_fixture(user: SpecSeed.user)
    property = fixture.fetch(:dataset_in_pool).dataset_properties.find_by!(name: 'referenced')
    old = DatasetPropertyHistory.create!(dataset_property: property, value: 1, created_at: 2.days.ago)
    recent = DatasetPropertyHistory.create!(dataset_property: property, value: 2, created_at: 12.hours.ago)

    expect { task.prune_property_logs }.to output("Deleted 1 dataset property logs\n").to_stdout

    expect(DatasetPropertyHistory.find_by(id: old.id)).to be_nil
    expect(DatasetPropertyHistory.find_by(id: recent.id)).to be_present
  end
end
