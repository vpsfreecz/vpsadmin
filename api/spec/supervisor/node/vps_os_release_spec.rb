# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::Supervisor::Node::VpsOsRelease do
  let(:node) { SpecSeed.node }
  let(:supervisor) { described_class.new(nil, node) }
  let(:timestamp) { Time.utc(2026, 4, 5, 20, 0, 0) }

  def os_release_payload(vps_id:, name: 'Debian GNU/Linux', id: 'debian', version_id: '13')
    {
      'vps_id' => vps_id,
      'time' => timestamp.to_i,
      'os_release' => {
        'NAME' => name,
        'ID' => id,
        'VERSION_ID' => version_id
      }
    }
  end

  describe '#update_vps_os_release' do
    it 'schedules an OS template update when the reported version has a matching template' do
      old_template = create_os_template!(distribution: 'debian', version: '12')
      new_template = create_os_template!(distribution: 'debian', version: '13')
      vps = build_standalone_vps_fixture(node:).fetch(:vps)
      vps.update!(os_template: old_template)
      allow(TransactionChains::Vps::Update).to receive(:fire2)

      supervisor.send(:update_vps_os_release, os_release_payload(vps_id: vps.id))

      expect(TransactionChains::Vps::Update).to have_received(:fire2).with(
        args: [vps, { os_template: new_template }],
        kwargs: {
          os_release: {
            'NAME' => 'Debian GNU/Linux',
            'ID' => 'debian',
            'VERSION_ID' => '13'
          }
        }
      )
    end

    it 'skips rolling distributions and releases without VERSION_ID' do
      vps = build_standalone_vps_fixture(node:).fetch(:vps)
      allow(TransactionChains::Vps::Update).to receive(:fire2)

      supervisor.send(
        :update_vps_os_release,
        os_release_payload(vps_id: vps.id, id: 'arch', version_id: nil)
      )

      expect(TransactionChains::Vps::Update).not_to have_received(:fire2)
    end

    it 'ignores unknown VPS ids' do
      allow(TransactionChains::Vps::Update).to receive(:fire2)

      expect do
        supervisor.send(:update_vps_os_release, os_release_payload(vps_id: Vps.maximum(:id).to_i + 10_000))
      end.not_to raise_error

      expect(TransactionChains::Vps::Update).not_to have_received(:fire2)
    end
  end

  describe '#os_release_to_template_version' do
    it 'translates distribution-specific version formats' do
      expect(supervisor.send(:os_release_to_template_version, 'Alpine Linux', 'alpine', '3.21.3'))
        .to eq(%w[alpine 3.21])
      expect(supervisor.send(:os_release_to_template_version, 'Rocky Linux', 'rocky', '9.4'))
        .to eq(%w[rocky 9])
      expect(supervisor.send(:os_release_to_template_version, 'openSUSE Leap', 'opensuse-leap', '15.6'))
        .to eq(%w[opensuse leap-15.6])
    end
  end
end
