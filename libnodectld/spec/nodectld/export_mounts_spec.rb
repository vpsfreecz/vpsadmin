# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/export_mounts'

RSpec.describe NodeCtld::ExportMounts do
  subject(:export_mounts) { described_class.send(:allocate) }

  let(:ct) do
    Struct.new(:id, :vps_id, :init_pid).new('123', 123, nil)
  end

  describe '#read_vps_mounts' do
    it 'returns an empty array when the init PID is unavailable' do
      allow(File).to receive(:open)

      expect(export_mounts.send(:read_vps_mounts, ct)).to eq([])
      expect(File).not_to have_received(:open)
    end
  end

  describe '#update_vps_keys' do
    it 'does not publish or raise when the init PID is unavailable' do
      allow(NodeCtld::NodeBunny).to receive(:publish_wait)

      expect { export_mounts.send(:update_vps_keys, ct) }.not_to raise_error
      expect(NodeCtld::NodeBunny).not_to have_received(:publish_wait)
    end
  end
end
