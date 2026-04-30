# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::Vps::UserDataUtils do
  subject(:helper) do
    Class.new do
      include VpsAdmin::API::Operations::Vps::UserDataUtils
    end.new
  end

  let(:template) { create_os_template!(enable_script: true, enable_cloud_init: true) }
  let(:vps) do
    Vps.new(
      user: SpecSeed.user,
      node: SpecSeed.node,
      os_template: template
    )
  end

  it 'rejects specifying stored and inline user data together' do
    user_data = create_vps_user_data!(
      user: SpecSeed.user,
      format: 'script',
      content: "#!/bin/sh\necho stored\n"
    )

    expect do
      helper.set_user_data(
        vps,
        {
          vps_user_data: user_data,
          user_data_format: 'script',
          user_data_content: "#!/bin/sh\necho inline\n"
        }
      )
    end.to raise_error(VpsAdmin::API::Exceptions::OperationError, /set either user_data/)
  end

  it 'builds valid inline user data and normalizes the options hash' do
    opts = {
      user_data_format: 'script',
      user_data_content: "#!/bin/sh\necho inline\n"
    }

    ret = helper.set_user_data(vps, opts)

    expect(ret).to eq(opts)
    expect(ret[:vps_user_data]).to be_a(VpsUserData)
    expect(ret[:vps_user_data]).to be_new_record
    expect(ret[:vps_user_data].user).to eq(SpecSeed.user)
    expect(ret[:vps_user_data].format).to eq('script')
    expect(ret).not_to include(:user_data_format, :user_data_content)
  end

  it 'raises RecordInvalid for invalid inline user data' do
    expect do
      helper.set_user_data(
        vps,
        {
          user_data_format: 'script',
          user_data_content: 'echo missing shebang'
        }
      )
    end.to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'denies access to user data owned by another user' do
    user_data = create_vps_user_data!(
      user: SpecSeed.other_user,
      format: 'script',
      content: "#!/bin/sh\necho foreign\n"
    )

    expect do
      helper.set_user_data(vps, { vps_user_data: user_data })
    end.to raise_error(VpsAdmin::API::Exceptions::OperationError, 'Access denied to VPS user data')
  end

  it 'rejects user data unsupported by the selected template' do
    user_data = create_vps_user_data!(
      user: SpecSeed.user,
      format: 'script',
      content: "#!/bin/sh\necho unsupported\n"
    )
    disabled_script_template = create_os_template!(enable_script: false)

    expect do
      helper.set_user_data(vps, { vps_user_data: user_data }, os_template: disabled_script_template)
    end.to raise_error(VpsAdmin::API::Exceptions::OperationError, /does not support script user data/)
  end

  it 'preserves supported stored user data' do
    user_data = create_vps_user_data!(
      user: SpecSeed.user,
      format: 'script',
      content: "#!/bin/sh\necho stored\n"
    )
    opts = { vps_user_data: user_data }

    expect(helper.set_user_data(vps, opts)).to eq(opts)
    expect(opts[:vps_user_data]).to eq(user_data)
  end
end
