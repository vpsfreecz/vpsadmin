# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::NotificationTemplate' do
  before do
    header 'Accept', 'application/json'
    SpecSeed.admin
    SpecSeed.user
  end

  let(:users) do
    {
      admin: SpecSeed.admin,
      user: SpecSeed.user
    }
  end

  let!(:fixtures) do
    tpl_a = NotificationTemplate.create!(
      name: 'spec_tpl_a',
      label: 'Spec Template A',
      template_id: 'daily_report',
      user_visibility: :default
    )

    tpl_b = NotificationTemplate.create!(
      name: 'spec_tpl_b',
      label: 'Spec Template B',
      template_id: 'dataset_migration_finished',
      user_visibility: :visible
    )

    recp_a = EmailRecipient.create!(label: 'Spec Recipient A', to: 'a@example.test')
    recp_b = EmailRecipient.create!(label: 'Spec Recipient B', cc: 'b@example.test')

    tpl_a_recp_a = NotificationTemplateEmailRecipient.create!(notification_template: tpl_a, email_recipient: recp_a)
    tpl_a_recp_b = NotificationTemplateEmailRecipient.create!(notification_template: tpl_a, email_recipient: recp_b)

    lang_en = Language.find_or_create_by!(code: 'en') { |l| l.label = 'English' }
    lang_cs = Language.find_or_create_by!(code: 'cs') { |l| l.label = 'Czech' }

    tr_en = NotificationTemplateVariant.create!(
      notification_template: tpl_a,
      language: lang_en,
      protocol: :email,
      from: 'noreply@example.test',
      subject: 'Spec EN subject',
      text: 'Hello EN',
      html: '<p>Hello EN</p>'
    )

    tr_cs = NotificationTemplateVariant.create!(
      notification_template: tpl_a,
      language: lang_cs,
      protocol: :email,
      from: 'noreply@example.test',
      subject: 'Spec CS subject',
      text: 'Ahoj CS'
    )

    {
      tpl_a: tpl_a,
      tpl_b: tpl_b,
      recp_a: recp_a,
      recp_b: recp_b,
      tpl_a_recp_a: tpl_a_recp_a,
      tpl_a_recp_b: tpl_a_recp_b,
      lang_en: lang_en,
      lang_cs: lang_cs,
      tr_en: tr_en,
      tr_cs: tr_cs
    }
  end

  def index_path
    vpath('/notification_templates')
  end

  def show_path(id)
    vpath("/notification_templates/#{id}")
  end

  def recipients_path(tpl_id)
    vpath("/notification_templates/#{tpl_id}/email_recipients")
  end

  def recipient_path(tpl_id, email_recipient_id)
    vpath("/notification_templates/#{tpl_id}/email_recipients/#{email_recipient_id}")
  end

  def variants_path(tpl_id)
    vpath("/notification_templates/#{tpl_id}/variants")
  end

  def variant_path(tpl_id, tr_id)
    vpath("/notification_templates/#{tpl_id}/variants/#{tr_id}")
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
    delete path, {}, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def admin
    users.fetch(:admin)
  end

  def user
    users.fetch(:user)
  end

  def tpl_a
    fixtures.fetch(:tpl_a)
  end

  def tpl_b
    fixtures.fetch(:tpl_b)
  end

  def recp_a
    fixtures.fetch(:recp_a)
  end

  def recp_b
    fixtures.fetch(:recp_b)
  end

  def tpl_a_recp_a
    fixtures.fetch(:tpl_a_recp_a)
  end

  def tpl_a_recp_b
    fixtures.fetch(:tpl_a_recp_b)
  end

  def lang_en
    fixtures.fetch(:lang_en)
  end

  def lang_cs
    fixtures.fetch(:lang_cs)
  end

  def tr_en
    fixtures.fetch(:tr_en)
  end

  def tr_cs
    fixtures.fetch(:tr_cs)
  end

  def template_create_payload
    {
      name: 'spec_tpl_created',
      label: 'Spec Template Created',
      template_id: 'daily_report',
      user_visibility: 'invisible'
    }
  end

  def variant_create_payload
    {
      protocol: 'email',
      language: lang_en.id,
      from: 'noreply@example.test',
      subject: 'Created subject',
      text: 'Hello',
      html: '<p>Hello</p>'
    }
  end

  def templates
    json.dig('response', 'notification_templates') || []
  end

  def template_obj
    json.dig('response', 'notification_template') || json['response']
  end

  def recipients_list
    json.dig('response', 'recipients') || json.dig('response', 'notification_template_recipients') || []
  end

  def recipient_obj
    json.dig('response', 'recipient') || json.dig('response', 'notification_template_recipient') || json['response']
  end

  def variants_list
    json.dig('response', 'variants') || json.dig('response', 'notification_template_variants') || []
  end

  def variant_obj
    json.dig('response', 'variant') || json.dig('response', 'notification_template_variant') || json['response']
  end

  def response_errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def msg
    json['message'] || json.dig('response', 'message') || json['error']
  end

  def action_input_params(resource_path, action_name)
    header 'Accept', 'application/json'
    options vpath('/')
    expect(last_response.status).to eq(200)

    data = json
    data = data['response'] if data.is_a?(Hash) && data['response'].is_a?(Hash)

    resources = data['resources'] || {}
    resource = nil
    resource_path.to_s.split('.').each do |part|
      resource = resources[part] || {}
      resources = resource['resources'] || {}
    end

    action = resource.dig('actions', action_name.to_s) || {}
    action.dig('input', 'parameters') || {}
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def rid(value)
    value.is_a?(Hash) ? value['id'] : value
  end

  describe 'API description' do
    it 'includes notification_template endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)

      expect(scopes).to include(
        'notification_template#index',
        'notification_template#show',
        'notification_template#create',
        'notification_template#update',
        'notification_template#delete',
        'notification_template.recipient#index',
        'notification_template.recipient#show',
        'notification_template.recipient#create',
        'notification_template.recipient#delete',
        'notification_template.variant#index',
        'notification_template.variant#show',
        'notification_template.variant#create',
        'notification_template.variant#update',
        'notification_template.variant#delete'
      )
    end

    it 'documents nullable variant input fields' do
      %w[create update].each do |action|
        input_params = action_input_params('notification_template.variant', action)

        expect(input_params.dig('reply_to', 'nullable')).to be(true)
        expect(input_params.dig('return_path', 'nullable')).to be(true)
        expect(input_params.dig('text', 'nullable')).to be(true)
        expect(input_params.dig('html', 'nullable')).to be(true)
      end
    end
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(user) { json_get index_path }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to list templates' do
      as(admin) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = templates.map { |row| row['id'] }
      expect(ids).to include(tpl_a.id, tpl_b.id)

      row = templates.detect { |item| item['id'] == tpl_a.id }
      expect(row).to include('id', 'name', 'label', 'template_id', 'user_visibility', 'created_at', 'updated_at')
    end

    it 'returns total_count meta when requested' do
      as(admin) { json_get index_path, _meta: { count: true } }

      expect_status(200)
      expect(json.dig('response', '_meta', 'total_count')).to eq(NotificationTemplate.count)
    end

    it 'supports limit pagination' do
      as(admin) { json_get index_path, notification_template: { limit: 1 } }

      expect_status(200)
      expect(templates.length).to eq(1)
    end

    it 'supports from_id pagination' do
      boundary = [tpl_a.id, tpl_b.id].min
      as(admin) { json_get index_path, notification_template: { from_id: boundary } }

      expect_status(200)
      ids = templates.map { |row| row['id'] }
      expect(ids).to all(be > boundary)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path(tpl_a.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(user) { json_get show_path(tpl_a.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to show a template' do
      as(admin) { json_get show_path(tpl_a.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(template_obj['id']).to eq(tpl_a.id)
      expect(template_obj['name']).to eq(tpl_a.name)
      expect(template_obj['label']).to eq(tpl_a.label)
      expect(template_obj['template_id']).to eq(tpl_a.template_id)
      expect(template_obj['user_visibility']).to eq(tpl_a.user_visibility)
    end

    it 'returns 404 for unknown template' do
      missing = NotificationTemplate.maximum(:id).to_i + 100

      as(admin) { json_get show_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Create' do
    it 'rejects unauthenticated access' do
      json_post index_path, notification_template: template_create_payload

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(user) { json_post index_path, notification_template: template_create_payload }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to create a template' do
      payload = template_create_payload
      as(admin) { json_post index_path, notification_template: payload }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(template_obj['name']).to eq(payload[:name])
      expect(template_obj['label']).to eq(payload[:label])
      expect(template_obj['template_id']).to eq(payload[:template_id])
      expect(template_obj['user_visibility']).to eq(payload[:user_visibility])

      created = NotificationTemplate.find_by!(name: payload[:name])
      expect(created.label).to eq(payload[:label])
      expect(created.template_id).to eq(payload[:template_id])
      expect(created.user_visibility).to eq(payload[:user_visibility])
    end

    it 'validates presence of name' do
      as(admin) { json_post index_path, notification_template: template_create_payload.except(:name) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys).to include('name')
    end

    it 'validates presence of label' do
      as(admin) { json_post index_path, notification_template: template_create_payload.except(:label) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys).to include('label')
    end

    it 'validates presence of template_id' do
      as(admin) { json_post index_path, notification_template: template_create_payload.except(:template_id) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys).to include('template_id')
    end

    it 'validates user_visibility choices' do
      as(admin) { json_post index_path, notification_template: template_create_payload.merge(user_visibility: 'nope') }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys).to include('user_visibility')
    end

    it 'validates name uniqueness' do
      as(admin) { json_post index_path, notification_template: template_create_payload.merge(name: tpl_a.name) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys).to include('name')
    end
  end

  describe 'Update' do
    it 'rejects unauthenticated access' do
      json_put show_path(tpl_a.id), notification_template: { label: 'Changed' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(user) { json_put show_path(tpl_a.id), notification_template: { label: 'Changed' } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to update a template' do
      as(admin) { json_put show_path(tpl_a.id), notification_template: { label: 'Changed', user_visibility: 'visible' } }

      expect_status(200)
      expect(json['status']).to be(true)

      tpl_a.reload
      expect(tpl_a.label).to eq('Changed')
      expect(tpl_a.user_visibility).to eq('visible')
    end

    it 'validates user_visibility choices' do
      as(admin) { json_put show_path(tpl_a.id), notification_template: { user_visibility: 'nope' } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys).to include('user_visibility')
    end

    it 'validates name uniqueness' do
      as(admin) { json_put show_path(tpl_b.id), notification_template: { name: tpl_a.name } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys).to include('name')
    end

    it 'returns 404 for unknown template' do
      missing = NotificationTemplate.maximum(:id).to_i + 100

      as(admin) { json_put show_path(missing), notification_template: { label: 'Changed' } }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Delete' do
    it 'rejects unauthenticated access' do
      json_delete show_path(tpl_a.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(user) { json_delete show_path(tpl_a.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to delete a template' do
      tpl_del = NotificationTemplate.create!(
        name: 'spec_tpl_del',
        label: 'Spec Template Delete',
        template_id: 'daily_report',
        user_visibility: :default
      )

      NotificationTemplateVariant.create!(
        notification_template: tpl_del,
        language: lang_en,
        protocol: :email,
        from: 'noreply@example.test',
        subject: 'Spec Delete subject',
        text: 'Delete me'
      )

      NotificationTemplateEmailRecipient.create!(notification_template: tpl_del, email_recipient: recp_a)

      as(admin) { json_delete show_path(tpl_del.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(NotificationTemplate.where(id: tpl_del.id)).to be_empty
      expect(NotificationTemplateVariant.where(notification_template_id: tpl_del.id)).to be_empty
      expect(NotificationTemplateEmailRecipient.where(notification_template_id: tpl_del.id)).to be_empty
    end

    it 'returns 404 for unknown template' do
      missing = NotificationTemplate.maximum(:id).to_i + 100

      as(admin) { json_delete show_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Recipient Index' do
    it 'rejects unauthenticated access' do
      json_get recipients_path(tpl_a.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(user) { json_get recipients_path(tpl_a.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'lists recipients for admin users' do
      as(admin) { json_get recipients_path(tpl_a.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(recipients_list.length).to eq(2)

      ids = recipients_list.map { |row| rid(row['email_recipient']) }
      expect(ids).to include(recp_a.id, recp_b.id)
    end

    it 'supports pagination limit' do
      as(admin) { json_get recipients_path(tpl_a.id), recipient: { limit: 1 } }

      expect_status(200)
      expect(recipients_list.length).to eq(1)
    end

    it 'supports pagination from_id' do
      boundary = [tpl_a_recp_a.id, tpl_a_recp_b.id].min
      as(admin) { json_get recipients_path(tpl_a.id), recipient: { from_id: boundary } }

      expect_status(200)
      ids = recipients_list.map { |row| row['id'] }
      expect(ids).to all(be > boundary)
    end
  end

  describe 'Recipient Show' do
    it 'rejects unauthenticated access' do
      json_get recipient_path(tpl_a.id, recp_a.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(user) { json_get recipient_path(tpl_a.id, recp_a.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'shows a recipient join for admin users' do
      as(admin) { json_get recipient_path(tpl_a.id, recp_a.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(rid(recipient_obj['email_recipient'])).to eq(recp_a.id)
    end

    it 'returns 404 for recipients not linked to template' do
      as(admin) { json_get recipient_path(tpl_b.id, recp_a.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'returns 404 for unknown template' do
      missing = NotificationTemplate.maximum(:id).to_i + 100

      as(admin) { json_get recipient_path(missing, recp_a.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'returns 404 for unknown recipient' do
      missing = EmailRecipient.maximum(:id).to_i + 100

      as(admin) { json_get recipient_path(tpl_a.id, missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Recipient Create' do
    it 'rejects unauthenticated access' do
      json_post recipients_path(tpl_b.id), recipient: { email_recipient: recp_a.id }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(user) { json_post recipients_path(tpl_b.id), recipient: { email_recipient: recp_a.id } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to create a recipient join' do
      as(admin) { json_post recipients_path(tpl_b.id), recipient: { email_recipient: recp_a.id } }

      expect_status(200)
      expect(json['status']).to be(true)
      NotificationTemplateEmailRecipient.find_by!(notification_template: tpl_b, email_recipient: recp_a)
    end

    it 'validates presence of email_recipient' do
      as(admin) { json_post recipients_path(tpl_b.id), recipient: {} }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys).to include('email_recipient')
    end

    it 'validates uniqueness of email_recipient per template' do
      as(admin) { json_post recipients_path(tpl_a.id), recipient: { email_recipient: recp_a.id } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys).to include('email_recipient')
    end
  end

  describe 'Recipient Delete' do
    it 'rejects unauthenticated access' do
      json_delete recipient_path(tpl_a.id, recp_a.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(user) { json_delete recipient_path(tpl_a.id, recp_a.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to delete a recipient join' do
      as(admin) { json_delete recipient_path(tpl_a.id, recp_a.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(NotificationTemplateEmailRecipient.where(notification_template: tpl_a, email_recipient: recp_a)).to be_empty
    end

    it 'returns 404 for unknown recipient join' do
      as(admin) { json_delete recipient_path(tpl_b.id, recp_a.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Variant Index' do
    it 'rejects unauthenticated access' do
      json_get variants_path(tpl_a.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(user) { json_get variants_path(tpl_a.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'lists variants for admin users' do
      as(admin) { json_get variants_path(tpl_a.id) }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = variants_list.map { |row| row['id'] }
      expect(ids).to include(tr_en.id, tr_cs.id)
    end

    it 'returns total_count meta when requested' do
      as(admin) { json_get variants_path(tpl_a.id), _meta: { count: true } }

      expect_status(200)
      expect(json.dig('response', '_meta', 'total_count')).to eq(tpl_a.notification_template_variants.count)
    end

    it 'supports limit pagination' do
      as(admin) { json_get variants_path(tpl_a.id), variant: { limit: 1 } }

      expect_status(200)
      expect(variants_list.length).to eq(1)
    end

    it 'supports from_id pagination' do
      boundary = [tr_en.id, tr_cs.id].min
      as(admin) { json_get variants_path(tpl_a.id), variant: { from_id: boundary } }

      expect_status(200)
      ids = variants_list.map { |row| row['id'] }
      expect(ids).to all(be > boundary)
    end
  end

  describe 'Variant Show' do
    it 'rejects unauthenticated access' do
      json_get variant_path(tpl_a.id, tr_en.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(user) { json_get variant_path(tpl_a.id, tr_en.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'shows a variant for admin users' do
      as(admin) { json_get variant_path(tpl_a.id, tr_en.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(rid(variant_obj['language'])).to eq(lang_en.id)
      expect(variant_obj['subject']).to eq(tr_en.subject)
    end

    it 'returns 404 for wrong template' do
      as(admin) { json_get variant_path(tpl_b.id, tr_en.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'returns 404 for unknown variant' do
      missing = NotificationTemplateVariant.maximum(:id).to_i + 100

      as(admin) { json_get variant_path(tpl_a.id, missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Variant Create' do
    it 'rejects unauthenticated access' do
      json_post variants_path(tpl_b.id), variant: variant_create_payload

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(user) { json_post variants_path(tpl_b.id), variant: variant_create_payload }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to create a variant' do
      as(admin) { json_post variants_path(tpl_b.id), variant: variant_create_payload }

      expect_status(200)
      expect(json['status']).to be(true)
      NotificationTemplateVariant.find_by!(notification_template: tpl_b, protocol: 'email', language: lang_en)
    end

    it 'validates presence of language' do
      as(admin) { json_post variants_path(tpl_b.id), variant: variant_create_payload.except(:language) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys).to include('language')
    end

    it 'validates presence of from' do
      as(admin) { json_post variants_path(tpl_b.id), variant: variant_create_payload.except(:from) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys).to include('from')
    end

    it 'validates presence of subject' do
      as(admin) { json_post variants_path(tpl_b.id), variant: variant_create_payload.except(:subject) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys).to include('subject')
    end

    it 'validates uniqueness of protocol and language per template' do
      as(admin) { json_post variants_path(tpl_a.id), variant: variant_create_payload.merge(language: lang_en.id) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys).to include('language')
    end
  end

  describe 'Variant Update' do
    it 'rejects unauthenticated access' do
      json_put variant_path(tpl_a.id, tr_en.id), variant: { subject: 'Updated subject' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(user) { json_put variant_path(tpl_a.id, tr_en.id), variant: { subject: 'Updated subject' } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to update a variant' do
      as(admin) { json_put variant_path(tpl_a.id, tr_en.id), variant: { subject: 'Updated subject', text: 'Updated text' } }

      expect_status(200)
      expect(json['status']).to be(true)

      tr_en.reload
      expect(tr_en.subject).to eq('Updated subject')
      expect(tr_en.text).to eq('Updated text')
    end

    it 'allows admin to clear optional variant fields' do
      tr_en.update!(
        reply_to: 'reply@example.test',
        return_path: 'bounce@example.test'
      )

      as(admin) do
        json_put variant_path(tpl_a.id, tr_en.id), variant: {
          reply_to: nil,
          return_path: nil,
          html: nil
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)

      tr_en.reload
      expect(tr_en.reply_to).to be_nil
      expect(tr_en.return_path).to be_nil
      expect(tr_en.text).to eq('Hello EN')
      expect(tr_en.html).to be_nil
    end

    it 'validates presence of subject' do
      as(admin) { json_put variant_path(tpl_a.id, tr_en.id), variant: { subject: '' } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys).to include('subject')
    end

    it 'returns 404 for unknown variant' do
      missing = NotificationTemplateVariant.maximum(:id).to_i + 100

      as(admin) { json_put variant_path(tpl_a.id, missing), variant: { subject: 'Updated subject' } }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'returns 404 for wrong template' do
      as(admin) { json_put variant_path(tpl_b.id, tr_en.id), variant: { subject: 'Updated subject' } }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Variant Delete' do
    it 'rejects unauthenticated access' do
      json_delete variant_path(tpl_a.id, tr_en.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(user) { json_delete variant_path(tpl_a.id, tr_en.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to delete a variant' do
      as(admin) { json_delete variant_path(tpl_a.id, tr_en.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(NotificationTemplateVariant.where(id: tr_en.id)).to be_empty
    end

    it 'returns 404 for unknown variant' do
      missing = NotificationTemplateVariant.maximum(:id).to_i + 100

      as(admin) { json_delete variant_path(tpl_a.id, missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end
end
