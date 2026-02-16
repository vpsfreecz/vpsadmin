# frozen_string_literal: true

require 'securerandom'

RSpec.describe 'VpsAdmin::API::Resources::VpsUserData' do
  before do
    header 'Accept', 'application/json'
    SpecSeed.user
    SpecSeed.other_user
    SpecSeed.admin
    SpecSeed.node
    SpecSeed.other_node
    SpecSeed.pool
    SpecSeed.other_pool
    SpecSeed.os_template
    SpecSeed.dns_resolver
  end

  def index_path
    vpath('/vps_user_data')
  end

  def show_path(id)
    vpath("/vps_user_data/#{id}")
  end

  def deploy_path(id)
    vpath("/vps_user_data/#{id}/deploy")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def json_post(path, payload)
    post path, JSON.dump(payload), {
      'CONTENT_TYPE' => 'application/json'
    }
  end

  def json_put(path, payload)
    put path, JSON.dump(payload), {
      'CONTENT_TYPE' => 'application/json'
    }
  end

  def json_delete(path)
    delete path, nil, {
      'CONTENT_TYPE' => 'application/json'
    }
  end

  def list
    json.dig('response', 'vps_user_data') || []
  end

  def obj
    json.dig('response', 'vps_user_data') || json['response']
  end

  def errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def msg
    json['message'] || json.dig('response', 'message') || json['error']
  end

  def action_state_id
    json.dig('response', '_meta', 'action_state_id') || json.dig('_meta', 'action_state_id')
  end

  def rid(value)
    value.is_a?(Hash) ? value['id'] : value
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected #{code} for #{path}, got #{last_response.status}: #{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def create_dataset_in_pool!(user:, pool:)
    dataset = Dataset.create!(
      name: "spec-#{SecureRandom.hex(4)}",
      user: user,
      user_editable: true,
      user_create: true,
      user_destroy: true,
      object_state: :active
    )

    DatasetInPool.create!(dataset: dataset, pool: pool)
  end

  def create_vps!(user:, node:, hostname:)
    pool = node == SpecSeed.other_node ? SpecSeed.other_pool : SpecSeed.pool
    dip = create_dataset_in_pool!(user: user, pool: pool)

    Vps.create!(
      user: user,
      node: node,
      hostname: hostname,
      os_template: SpecSeed.os_template,
      dns_resolver: SpecSeed.dns_resolver,
      dataset_in_pool: dip,
      object_state: :active
    )
  end

  def create_user_data!(user:, label:, format:, content:)
    VpsUserData.create!(
      user: user,
      label: label,
      format: format,
      content: content
    )
  end

  def script_content
    "#!/bin/sh\necho hello\n"
  end

  def cloudinit_script_content
    "#!/bin/bash\necho cloud-init\n"
  end

  def cloudinit_config_content
    "---\npackage_update: true\n"
  end

  def nixos_configuration_content
    '{ config, pkgs, ... }: { }'
  end

  def nixos_flake_configuration_content
    '{ inputs, ... }: { }'
  end

  def nixos_flake_uri_content
    'github:example/repo'
  end

  describe 'API description' do
    it 'includes vps user data endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)

      expect(scopes).to include(
        'vps_user_data#index',
        'vps_user_data#show',
        'vps_user_data#create',
        'vps_user_data#update',
        'vps_user_data#deploy',
        'vps_user_data#delete'
      )
    end
  end

  describe 'Index' do
    let(:index_data) do
      {
        user_script: create_user_data!(
          user: SpecSeed.user,
          label: 'User Script',
          format: 'script',
          content: script_content
        ),
        user_cloudinit: create_user_data!(
          user: SpecSeed.user,
          label: 'User Cloud-Init',
          format: 'cloudinit_config',
          content: cloudinit_config_content
        ),
        other_script: create_user_data!(
          user: SpecSeed.other_user,
          label: 'Other Script',
          format: 'script',
          content: script_content
        )
      }
    end

    it 'rejects unauthenticated access' do
      json_get index_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'lists only own data for normal users' do
      data = index_data
      as(SpecSeed.user) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = list.map { |row| row['id'] }
      expect(ids).to include(data[:user_script].id, data[:user_cloudinit].id)
      expect(ids).not_to include(data[:other_script].id)

      row = list.find { |item| item['id'] == data[:user_script].id }
      expect(row).to include('id', 'user', 'label', 'format', 'content', 'created_at', 'updated_at')
      expect(rid(row['user'])).to eq(SpecSeed.user.id)
    end

    it 'allows admin to list all' do
      data = index_data
      as(SpecSeed.admin) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = list.map { |row| row['id'] }
      expect(ids).to include(data[:user_script].id, data[:user_cloudinit].id, data[:other_script].id)
    end

    it 'filters by format for users and admins' do
      data = index_data
      as(SpecSeed.user) { json_get index_path, vps_user_data: { format: 'script' } }

      expect_status(200)
      ids = list.map { |row| row['id'] }
      expect(ids).to include(data[:user_script].id)
      expect(ids).not_to include(data[:user_cloudinit].id, data[:other_script].id)

      as(SpecSeed.admin) { json_get index_path, vps_user_data: { format: 'script' } }

      expect_status(200)
      ids = list.map { |row| row['id'] }
      expect(ids).to include(data[:user_script].id, data[:other_script].id)
      expect(ids).not_to include(data[:user_cloudinit].id)
    end

    it 'allows admins to filter by user' do
      data = index_data
      as(SpecSeed.admin) { json_get index_path, vps_user_data: { user: SpecSeed.user.id } }

      expect_status(200)
      ids = list.map { |row| row['id'] }
      expect(ids).to include(data[:user_script].id, data[:user_cloudinit].id)
      expect(ids).not_to include(data[:other_script].id)
    end

    it 'ignores user filter for normal users' do
      data = index_data
      as(SpecSeed.user) do
        json_get index_path, vps_user_data: { user: SpecSeed.other_user.id }
      end

      expect_status(200)
      ids = list.map { |row| row['id'] }
      expect(ids).to include(data[:user_script].id, data[:user_cloudinit].id)
      expect(ids).not_to include(data[:other_script].id)
    end

    it 'supports limit pagination' do
      index_data
      as(SpecSeed.admin) { json_get index_path, vps_user_data: { limit: 1 } }

      expect_status(200)
      expect(list.length).to eq(1)
    end

    it 'supports from_id pagination' do
      index_data
      boundary = VpsUserData.order(:id).first.id
      as(SpecSeed.admin) { json_get index_path, vps_user_data: { from_id: boundary } }

      expect_status(200)
      ids = list.map { |row| row['id'] }
      expect(ids).to all(be > boundary)
    end

    it 'returns total_count meta when requested' do
      index_data
      as(SpecSeed.admin) { json_get index_path, _meta: { count: true } }

      expect_status(200)
      expect(json.dig('response', '_meta', 'total_count')).to eq(VpsUserData.count)
    end
  end

  describe 'Show' do
    let(:user_row) do
      create_user_data!(
        user: SpecSeed.user,
        label: 'User Data',
        format: 'script',
        content: script_content
      )
    end

    let(:other_row) do
      create_user_data!(
        user: SpecSeed.other_user,
        label: 'Other Data',
        format: 'cloudinit_script',
        content: cloudinit_script_content
      )
    end

    it 'rejects unauthenticated access' do
      json_get show_path(user_row.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows owner to show' do
      as(SpecSeed.user) { json_get show_path(user_row.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(obj['id']).to eq(user_row.id)
      expect(rid(obj['user'])).to eq(SpecSeed.user.id)
    end

    it 'hides other users records' do
      other_row
      as(SpecSeed.user) { json_get show_path(other_row.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admin to show any' do
      as(SpecSeed.admin) { json_get show_path(other_row.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(obj['id']).to eq(other_row.id)
    end

    it 'returns 404 for unknown id' do
      other_row
      missing_id = VpsUserData.maximum(:id).to_i + 100

      as(SpecSeed.admin) { json_get show_path(missing_id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Create' do
    let(:payload) do
      {
        label: "Spec Data #{SecureRandom.hex(3)}",
        format: 'script',
        content: script_content
      }
    end

    it 'rejects unauthenticated access' do
      json_post index_path, vps_user_data: payload

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows normal user to create for self' do
      expect do
        as(SpecSeed.user) { json_post index_path, vps_user_data: payload }
      end.to change(VpsUserData, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)
      expect(rid(obj['user'])).to eq(SpecSeed.user.id)

      record = VpsUserData.find_by!(label: payload[:label])
      expect(record.user_id).to eq(SpecSeed.user.id)
    end

    it 'ignores user field for non-admins' do
      payload_with_user = payload.merge(user: SpecSeed.other_user.id)

      expect do
        as(SpecSeed.user) { json_post index_path, vps_user_data: payload_with_user }
      end.to change(VpsUserData, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)

      record = VpsUserData.find_by!(label: payload_with_user[:label])
      expect(record.user_id).to eq(SpecSeed.user.id)
    end

    it 'allows admin to create for another user' do
      payload_with_user = payload.merge(user: SpecSeed.other_user.id)

      expect do
        as(SpecSeed.admin) { json_post index_path, vps_user_data: payload_with_user }
      end.to change(VpsUserData, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)

      record = VpsUserData.find_by!(label: payload_with_user[:label])
      expect(record.user_id).to eq(SpecSeed.other_user.id)
    end

    it 'returns validation errors for missing label' do
      as(SpecSeed.admin) { json_post index_path, vps_user_data: payload.except(:label) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('label')
    end

    it 'returns validation errors for missing format' do
      as(SpecSeed.admin) do
        json_post index_path, vps_user_data: payload.merge(format: nil)
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('format')
    end

    it 'returns validation errors for missing content' do
      as(SpecSeed.admin) do
        json_post index_path, vps_user_data: payload.merge(format: 'nixos_flake_uri', content: nil)
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('content')
    end

    it 'returns validation errors for invalid format' do
      as(SpecSeed.admin) do
        json_post index_path, vps_user_data: payload.merge(format: 'nope')
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('format')
    end

    it 'validates script content requires a shebang' do
      as(SpecSeed.admin) do
        json_post index_path, vps_user_data: payload.merge(format: 'script', content: "echo hi\n")
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('content')
      content_errors = Array(errors['content'] || errors[:content]).join(' ')
      expect(content_errors).to include('shebang')
    end

    it 'validates cloudinit_config YAML' do
      as(SpecSeed.admin) do
        json_post index_path, vps_user_data: payload.merge(
          format: 'cloudinit_config',
          content: ':::not-yaml:::'
        )
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('content')
      content_errors = Array(errors['content'] || errors[:content]).join(' ')
      expect(content_errors).to include('unable to parse as YAML')
    end

    it 'validates nixos_flake_uri without whitespace' do
      as(SpecSeed.admin) do
        json_post index_path, vps_user_data: payload.merge(
          format: 'nixos_flake_uri',
          content: 'github:owner/repo withspace'
        )
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('content')
      content_errors = Array(errors['content'] || errors[:content]).join(' ')
      expect(content_errors).to include('must not contain whitespace')
    end

    it 'validates content size limits' do
      oversized = 'a' * 65_537
      as(SpecSeed.admin) do
        json_post index_path, vps_user_data: payload.merge(
          format: 'nixos_flake_uri',
          content: oversized
        )
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('content')
    end
  end

  describe 'Update' do
    let(:user_row) do
      create_user_data!(
        user: SpecSeed.user,
        label: 'User Update',
        format: 'script',
        content: script_content
      )
    end

    let(:other_row) do
      create_user_data!(
        user: SpecSeed.other_user,
        label: 'Other Update',
        format: 'cloudinit_script',
        content: cloudinit_script_content
      )
    end

    it 'rejects unauthenticated access' do
      json_put show_path(user_row.id), vps_user_data: { label: 'Updated' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows owner to update label' do
      new_label = "Updated #{SecureRandom.hex(3)}"
      as(SpecSeed.user) { json_put show_path(user_row.id), vps_user_data: { label: new_label } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(obj['label']).to eq(new_label)
      expect(user_row.reload.label).to eq(new_label)
    end

    it 'allows owner to update format and content' do
      as(SpecSeed.user) do
        json_put show_path(user_row.id), vps_user_data: {
          format: 'cloudinit_config',
          content: cloudinit_config_content
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(user_row.reload.format).to eq('cloudinit_config')
      expect(user_row.content).to eq(cloudinit_config_content)
    end

    it 'returns validation errors for invalid update' do
      as(SpecSeed.user) do
        json_put show_path(user_row.id), vps_user_data: {
          format: 'script',
          content: "echo hi\n"
        }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('content')
    end

    it 'prevents users from updating other user records' do
      as(SpecSeed.user) do
        json_put show_path(other_row.id), vps_user_data: { label: 'Nope' }
      end

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admin to update any record' do
      new_label = "Admin Update #{SecureRandom.hex(3)}"
      as(SpecSeed.admin) do
        json_put show_path(other_row.id), vps_user_data: { label: new_label }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(other_row.reload.label).to eq(new_label)
    end

    it 'accepts empty update payloads as no-op' do
      original = {
        label: user_row.label,
        format: user_row.format,
        content: user_row.content
      }

      as(SpecSeed.user) { json_put show_path(user_row.id), vps_user_data: {} }

      expect_status(200)
      expect(json['status']).to be(true)

      user_row.reload
      expect(user_row.label).to eq(original[:label])
      expect(user_row.format).to eq(original[:format])
      expect(user_row.content).to eq(original[:content])
    end
  end

  describe 'Deploy' do
    let(:user_data) do
      create_user_data!(
        user: SpecSeed.user,
        label: 'User Deploy',
        format: 'script',
        content: script_content
      )
    end

    let(:other_user_data) do
      create_user_data!(
        user: SpecSeed.other_user,
        label: 'Other Deploy',
        format: 'cloudinit_config',
        content: cloudinit_config_content
      )
    end

    let(:user_vps) do
      create_vps!(
        user: SpecSeed.user,
        node: SpecSeed.node,
        hostname: 'user-vps'
      )
    end

    let(:other_vps) do
      create_vps!(
        user: SpecSeed.other_user,
        node: SpecSeed.node,
        hostname: 'other-vps'
      )
    end

    it 'rejects unauthenticated access' do
      json_post deploy_path(user_data.id), vps_user_data: { vps: user_vps.id }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows owner to deploy to their VPS' do
      ensure_signer_unlocked!

      as(SpecSeed.user) do
        json_post deploy_path(user_data.id), vps_user_data: { vps: user_vps.id }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(action_state_id.to_i).to be > 0

      chain = TransactionChain.find(action_state_id)
      expect(chain.user_id).to eq(SpecSeed.user.id)
      expect(chain.state).to be_in(%w[queued pending])
      expect(chain.transactions.count).to eq(1)

      tx = chain.transactions.first
      parsed = JSON.parse(tx.input)
      expect(parsed.dig('input', 'format')).to eq(user_data.format)
      expect(parsed.dig('input', 'content')).to eq(user_data.content)
      expect(parsed.dig('input', 'os_template', 'distribution')).to eq(
        SpecSeed.os_template.distribution
      )
    end

    it 'denies mismatched VPS/user_data even for admins' do
      ensure_signer_unlocked!

      expect do
        as(SpecSeed.admin) do
          json_post deploy_path(user_data.id), vps_user_data: { vps: other_vps.id }
        end
      end.not_to change(TransactionChain, :count)

      expect_status(200)
      expect(json['status']).to be(false)
      expect(msg).to include('access denied')
      expect(action_state_id).to be_nil
    end

    it 'prevents users from deploying other user data' do
      as(SpecSeed.user) do
        json_post deploy_path(other_user_data.id), vps_user_data: { vps: user_vps.id }
      end

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'returns validation errors for missing vps' do
      as(SpecSeed.user) { json_post deploy_path(user_data.id), vps_user_data: {} }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('vps')
    end
  end

  describe 'Delete' do
    let(:user_row) do
      create_user_data!(
        user: SpecSeed.user,
        label: 'User Delete',
        format: 'script',
        content: script_content
      )
    end

    let(:other_row) do
      create_user_data!(
        user: SpecSeed.other_user,
        label: 'Other Delete',
        format: 'cloudinit_script',
        content: cloudinit_script_content
      )
    end

    it 'rejects unauthenticated access' do
      json_delete show_path(user_row.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows owner to delete' do
      user_row
      expect do
        as(SpecSeed.user) { json_delete show_path(user_row.id) }
      end.to change(VpsUserData, :count).by(-1)

      expect_status(200)
      expect(json['status']).to be(true)
      expect(VpsUserData.find_by(id: user_row.id)).to be_nil
    end

    it 'prevents users from deleting other user data' do
      as(SpecSeed.user) { json_delete show_path(other_row.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'allows admin to delete any record' do
      other_row
      expect do
        as(SpecSeed.admin) { json_delete show_path(other_row.id) }
      end.to change(VpsUserData, :count).by(-1)

      expect_status(200)
      expect(json['status']).to be(true)
    end

    it 'returns 404 for unknown id' do
      other_row
      missing_id = VpsUserData.maximum(:id).to_i + 100

      as(SpecSeed.admin) { json_delete show_path(missing_id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end
end
