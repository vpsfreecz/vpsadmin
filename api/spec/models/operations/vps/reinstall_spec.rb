# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::Vps::Reinstall do
  around do |example|
    with_current_context(user: SpecSeed.user) { example.run }
  end

  let(:vps) { build_standalone_vps_fixture.fetch(:vps) }

  it 'rejects disabled templates' do
    template = create_os_template!(enabled: false)

    expect do
      described_class.run(vps, os_template: template)
    end.to raise_error(VpsAdmin::API::Exceptions::OperationError, 'selected os template is disabled')
  end

  it 'rejects templates for a different hypervisor type' do
    template = create_os_template!
    template.update!(hypervisor_type: :openvz)

    expect do
      described_class.run(vps, os_template: template)
    end.to raise_error(VpsAdmin::API::Exceptions::OperationError, /incompatible template/)
  end

  it 'rejects templates for an incompatible cgroup version' do
    ensure_available_node_status!(vps.node)
    template = create_os_template!(cgroup_version: :cgroup_v1)

    expect do
      described_class.run(vps, os_template: template)
    end.to raise_error(VpsAdmin::API::Exceptions::OperationError, /incompatible cgroup version/)
  end

  it 'normalizes user data, delegates to the reinstall chain, and returns only the chain' do
    template = create_os_template!(enable_script: true)
    opts = {
      os_template: template,
      user_data_format: 'script',
      user_data_content: "#!/bin/sh\necho reinstall\n"
    }
    chain = instance_double(TransactionChain)

    allow(TransactionChains::Vps::Reinstall).to receive(:fire) do |arg_vps, arg_template, chain_opts|
      expect(arg_vps).to eq(vps)
      expect(arg_template).to eq(template)
      expect(chain_opts[:vps_user_data]).to be_a(VpsUserData)
      expect(chain_opts).not_to include(:user_data_format, :user_data_content)
      [chain, arg_vps]
    end

    expect(described_class.run(vps, opts)).to eq(chain)
  end
end
