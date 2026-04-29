# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::Supervisor::Node::StorageStatus do
  let(:node) { SpecSeed.node }
  let(:supervisor) { described_class.new(nil, node) }
  let(:timestamp) { Time.utc(2026, 4, 5, 14, 0, 0) }

  def property_payload(prop, value, vps: nil)
    {
      'id' => prop.id,
      'name' => prop.name,
      'value' => value,
      'vps_id' => vps&.id
    }
  end

  describe '#update_dataset_properties' do
    it 'updates integer property values in MiB and refreshes VPS disk sums' do
      fixture = build_standalone_vps_fixture(node:)
      vps = fixture.fetch(:vps)
      dip = fixture.fetch(:dataset_in_pool)
      refquota = dip.dataset_properties.find_by!(name: 'refquota')
      referenced = dip.dataset_properties.find_by!(name: 'referenced')
      set_vps_running!(vps)

      supervisor.send(
        :update_dataset_properties,
        {
          'time' => timestamp.to_i,
          'message_id' => described_class::LOG_NTH_MESSAGE,
          'properties' => [
            property_payload(refquota, 10 * 1024 * 1024 * 1024, vps:),
            property_payload(referenced, 4 * 1024 * 1024 * 1024, vps:)
          ]
        }
      )

      expect(refquota.reload.value).to eq(10_240)
      expect(referenced.reload.value).to eq(4096)
      expect(refquota.updated_at).to eq(timestamp)
      expect(referenced.updated_at).to eq(timestamp)

      status = vps.vps_current_status.reload
      expect(status.total_diskspace).to eq(10_240)
      expect(status.used_diskspace).to eq(4096)

      expect(DatasetPropertyHistory.where(dataset_property: refquota)).to be_empty
      history = DatasetPropertyHistory.find_by!(dataset_property: referenced)
      expect(history.value).to eq(4096)
      expect(history.created_at).to eq(timestamp)
    end

    it 'preserves floating point compression ratios' do
      dip = build_standalone_vps_fixture(node:).fetch(:dataset_in_pool)
      compressratio = dip.dataset_properties.find_by!(name: 'compressratio')

      supervisor.send(
        :update_dataset_properties,
        {
          'time' => timestamp.to_i,
          'message_id' => 1,
          'properties' => [
            property_payload(compressratio, 1.75)
          ]
        }
      )

      expect(compressratio.reload.value).to eq(1.75)
    end

    it 'does not create history rows for non-logging messages' do
      dip = build_standalone_vps_fixture(node:).fetch(:dataset_in_pool)
      used = dip.dataset_properties.find_by!(name: 'used')

      supervisor.send(
        :update_dataset_properties,
        {
          'time' => timestamp.to_i,
          'message_id' => described_class::LOG_NTH_MESSAGE + 1,
          'properties' => [
            property_payload(used, 64 * 1024 * 1024)
          ]
        }
      )

      expect(used.reload.value).to eq(64)
      expect(DatasetPropertyHistory.where(dataset_property: used)).to be_empty
    end
  end
end
