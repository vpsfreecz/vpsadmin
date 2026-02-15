# frozen_string_literal: true

require 'securerandom'

RSpec.describe 'VpsAdmin::API::Resources::User::MailTemplateRecipient' do
  before do
    header 'Accept', 'application/json'
  end

  def index_path(user_id)
    vpath("/users/#{user_id}/mail_template_recipients")
  end

  def show_path(user_id, tpl_name)
    vpath("/users/#{user_id}/mail_template_recipients/#{tpl_name}")
  end

  def update_path(user_id, tpl_name)
    vpath("/users/#{user_id}/mail_template_recipients/#{tpl_name}")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def json_put(path, payload)
    put path, JSON.dump(payload), { 'CONTENT_TYPE' => 'application/json' }
  end

  def list
    json.dig('response', 'mail_template_recipients') || []
  end

  def obj
    json.dig('response', 'mail_template_recipient') || json['response']
  end

  def errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def response_message
    json['message'] || json.dig('response', 'message')
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def create_template(template_id:, user_visibility:, name_prefix:)
    name = "#{name_prefix}_#{SecureRandom.hex(4)}"
    MailTemplate.create!(
      name: name,
      label: name.tr('_', ' ').capitalize,
      template_id: template_id,
      user_visibility: user_visibility
    )
  end

  let(:user) { SpecSeed.user }
  let(:other_user) { SpecSeed.other_user }
  let(:admin) { SpecSeed.admin }
  let!(:templates) do
    tpl_public_saved = create_template(
      template_id: 'user_suspend',
      user_visibility: :default,
      name_prefix: 'spec_umtr_pub_saved'
    )
    tpl_public_placeholder = create_template(
      template_id: 'user_resume',
      user_visibility: :default,
      name_prefix: 'spec_umtr_pub_placeholder'
    )
    tpl_nonpub_visible = create_template(
      template_id: 'user_create',
      user_visibility: :visible,
      name_prefix: 'spec_umtr_nonpub_visible'
    )
    tpl_invisible = create_template(
      template_id: 'user_soft_delete',
      user_visibility: :invisible,
      name_prefix: 'spec_umtr_invisible'
    )

    UserMailTemplateRecipient.create!(
      user: user,
      mail_template: tpl_public_saved,
      to: 'saved1@test.invalid',
      enabled: true
    )
    UserMailTemplateRecipient.create!(
      user: user,
      mail_template: tpl_nonpub_visible,
      to: 'saved2@test.invalid',
      enabled: true
    )
    UserMailTemplateRecipient.create!(
      user: user,
      mail_template: tpl_invisible,
      to: 'hidden@test.invalid',
      enabled: true
    )
    UserMailTemplateRecipient.create!(
      user: other_user,
      mail_template: tpl_public_saved,
      to: 'other@test.invalid',
      enabled: true
    )

    {
      public_saved: tpl_public_saved,
      public_placeholder: tpl_public_placeholder,
      nonpub_visible: tpl_nonpub_visible,
      invisible: tpl_invisible
    }
  end

  def tpl_public_saved
    templates.fetch(:public_saved)
  end

  def tpl_public_placeholder
    templates.fetch(:public_placeholder)
  end

  def tpl_nonpub_visible
    templates.fetch(:nonpub_visible)
  end

  def tpl_invisible
    templates.fetch(:invisible)
  end

  describe 'API description' do
    it 'includes mail template recipient endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)
      expect(scopes).to include(
        'user.mail_template_recipient#index',
        'user.mail_template_recipient#show',
        'user.mail_template_recipient#update'
      )
    end
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path(user.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'lists templates for the user with placeholders and filters' do
      as(user) { json_get index_path(user.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(list).to be_a(Array)

      ids = list.map { |row| row['id'] }
      expect(ids).to include(tpl_public_saved.name, tpl_public_placeholder.name, tpl_nonpub_visible.name)
      expect(ids).not_to include(tpl_invisible.name)
      expect(ids).to eq(ids.sort)

      placeholder_row = list.find { |row| row['id'] == tpl_public_placeholder.name }
      expect(placeholder_row['to']).to be_nil

      sample_row = list.first
      expect(sample_row).to include('id', 'label', 'description', 'to', 'enabled')
    end

    it 'returns total_count meta when requested' do
      templates
      as(user) { json_get index_path(user.id), _meta: { count: true } }

      expect_status(200)
      expect(json.dig('response', '_meta', 'total_count')).to eq(list.length)
    end

    it 'denies user listing another user recipients' do
      as(user) { json_get index_path(other_user.id) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to match(/access denied/i)
    end

    it 'allows admin listing another user recipients' do
      tpl_public_saved

      as(admin) { json_get index_path(other_user.id) }

      expect_status(200)
      expect(json['status']).to be(true)
    end

    it 'returns 404 for unknown user' do
      as(admin) { json_get index_path(999_999_999) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path(user.id, tpl_public_saved.name)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'shows a saved recipient record' do
      as(user) { json_get show_path(user.id, tpl_public_saved.name) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(obj['id']).to eq(tpl_public_saved.name)
      expect(obj['to']).to eq('saved1@test.invalid')
      expect(obj['enabled']).to be(true)
    end

    it 'returns 404 for placeholder template without saved record' do
      as(user) { json_get show_path(user.id, tpl_public_placeholder.name) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'denies user showing another user recipient' do
      as(user) { json_get show_path(other_user.id, tpl_public_saved.name) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to match(/access denied/i)
    end

    it 'allows admin to show another user recipient' do
      as(admin) { json_get show_path(other_user.id, tpl_public_saved.name) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(obj['id']).to eq(tpl_public_saved.name)
      expect(obj['to']).to eq('other@test.invalid')
    end

    it 'returns 404 for unknown template name' do
      as(user) { json_get show_path(user.id, 'does-not-exist') }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Update' do
    it 'rejects unauthenticated access' do
      json_put update_path(user.id, tpl_public_saved.name),
               mail_template_recipient: { to: 'x@test.invalid' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'updates recipients and strips whitespace' do
      payload = { mail_template_recipient: { to: ' new@test.invalid , second@test.invalid ' } }

      as(user) { json_put update_path(user.id, tpl_public_saved.name), payload }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(obj['to']).to eq('new@test.invalid,second@test.invalid')

      recp = UserMailTemplateRecipient.find_by!(user: user, mail_template: tpl_public_saved)
      expect(recp.to).to eq('new@test.invalid,second@test.invalid')
    end

    it 'rejects invalid email address' do
      UserMailTemplateRecipient.where(user: user, mail_template: tpl_public_saved).delete_all

      as(user) do
        json_put update_path(user.id, tpl_public_saved.name),
                 mail_template_recipient: { to: 'invalid-email' }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(json['message']).to eq('Update failed')

      error_keys = errors.keys.map(&:to_s)
      expect(error_keys).to include('to')
    end

    it 'removes saved record when resetting to defaults' do
      expect(UserMailTemplateRecipient.where(user: user, mail_template: tpl_public_saved)).not_to be_empty

      payload = { mail_template_recipient: { to: '', enabled: true } }

      as(user) { json_put update_path(user.id, tpl_public_saved.name), payload }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(UserMailTemplateRecipient.where(user: user, mail_template: tpl_public_saved)).to be_empty
    end

    it 'keeps a record when disabling template' do
      UserMailTemplateRecipient.where(user: user, mail_template: tpl_public_saved).delete_all

      payload = { mail_template_recipient: { to: '', enabled: false } }

      as(user) { json_put update_path(user.id, tpl_public_saved.name), payload }

      expect_status(200)
      expect(json['status']).to be(true)

      recp = UserMailTemplateRecipient.find_by!(user: user, mail_template: tpl_public_saved)
      expect(recp.enabled).to be(false)
      expect(recp.to).to be_in([nil, ''])
    end

    it 'denies updating another user recipient' do
      payload = { mail_template_recipient: { to: 'x@test.invalid' } }

      as(user) { json_put update_path(other_user.id, tpl_public_saved.name), payload }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to match(/access denied/i)
    end

    it 'allows admin to update another user recipient' do
      payload = { mail_template_recipient: { to: 'admin@test.invalid' } }

      as(admin) { json_put update_path(other_user.id, tpl_public_saved.name), payload }

      expect_status(200)
      expect(json['status']).to be(true)

      recp = UserMailTemplateRecipient.find_by!(user: other_user, mail_template: tpl_public_saved)
      expect(recp.to).to eq('admin@test.invalid')
    end

    it 'returns 404 for unknown template name' do
      payload = { mail_template_recipient: { to: 'x@test.invalid' } }

      as(user) { json_put update_path(user.id, 'does-not-exist'), payload }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end
end
