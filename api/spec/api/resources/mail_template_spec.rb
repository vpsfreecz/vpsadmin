# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::MailTemplate' do
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
    tpl_a = MailTemplate.create!(
      name: 'spec_tpl_a',
      label: 'Spec Template A',
      template_id: 'daily_report',
      user_visibility: :default
    )

    tpl_b = MailTemplate.create!(
      name: 'spec_tpl_b',
      label: 'Spec Template B',
      template_id: 'dataset_migration_finished',
      user_visibility: :visible
    )

    recp_a = MailRecipient.create!(label: 'Spec Recipient A', to: 'a@example.test')
    recp_b = MailRecipient.create!(label: 'Spec Recipient B', cc: 'b@example.test')

    tpl_a_recp_a = MailTemplateRecipient.create!(mail_template: tpl_a, mail_recipient: recp_a)
    tpl_a_recp_b = MailTemplateRecipient.create!(mail_template: tpl_a, mail_recipient: recp_b)

    lang_en = Language.find_or_create_by!(code: 'en') { |l| l.label = 'English' }
    lang_cs = Language.find_or_create_by!(code: 'cs') { |l| l.label = 'Czech' }

    tr_en = MailTemplateTranslation.create!(
      mail_template: tpl_a,
      language: lang_en,
      from: 'noreply@example.test',
      subject: 'Spec EN subject',
      text_plain: 'Hello EN',
      text_html: '<p>Hello EN</p>'
    )

    tr_cs = MailTemplateTranslation.create!(
      mail_template: tpl_a,
      language: lang_cs,
      from: 'noreply@example.test',
      subject: 'Spec CS subject',
      text_plain: 'Ahoj CS'
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
    vpath('/mail_templates')
  end

  def show_path(id)
    vpath("/mail_templates/#{id}")
  end

  def recipients_path(tpl_id)
    vpath("/mail_templates/#{tpl_id}/recipients")
  end

  def recipient_path(tpl_id, mail_recipient_id)
    vpath("/mail_templates/#{tpl_id}/recipients/#{mail_recipient_id}")
  end

  def translations_path(tpl_id)
    vpath("/mail_templates/#{tpl_id}/translations")
  end

  def translation_path(tpl_id, tr_id)
    vpath("/mail_templates/#{tpl_id}/translations/#{tr_id}")
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

  def translation_create_payload
    {
      language: lang_en.id,
      from: 'noreply@example.test',
      subject: 'Created subject',
      text_plain: 'Hello',
      text_html: '<p>Hello</p>'
    }
  end

  def templates
    json.dig('response', 'mail_templates') || []
  end

  def template_obj
    json.dig('response', 'mail_template') || json['response']
  end

  def recipients_list
    json.dig('response', 'recipients') || json.dig('response', 'mail_template_recipients') || []
  end

  def recipient_obj
    json.dig('response', 'recipient') || json.dig('response', 'mail_template_recipient') || json['response']
  end

  def translations_list
    json.dig('response', 'translations') || json.dig('response', 'mail_template_translations') || []
  end

  def translation_obj
    json.dig('response', 'translation') || json.dig('response', 'mail_template_translation') || json['response']
  end

  def response_errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def msg
    json['message'] || json.dig('response', 'message') || json['error']
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
    it 'includes mail_template endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)

      expect(scopes).to include(
        'mail_template#index',
        'mail_template#show',
        'mail_template#create',
        'mail_template#update',
        'mail_template#delete',
        'mail_template.recipient#index',
        'mail_template.recipient#show',
        'mail_template.recipient#create',
        'mail_template.recipient#delete',
        'mail_template.translation#index',
        'mail_template.translation#show',
        'mail_template.translation#create',
        'mail_template.translation#update',
        'mail_template.translation#delete'
      )
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
      expect(json.dig('response', '_meta', 'total_count')).to eq(MailTemplate.count)
    end

    it 'supports limit pagination' do
      as(admin) { json_get index_path, mail_template: { limit: 1 } }

      expect_status(200)
      expect(templates.length).to eq(1)
    end

    it 'supports from_id pagination' do
      boundary = [tpl_a.id, tpl_b.id].min
      as(admin) { json_get index_path, mail_template: { from_id: boundary } }

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
      missing = MailTemplate.maximum(:id).to_i + 100

      as(admin) { json_get show_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Create' do
    it 'rejects unauthenticated access' do
      json_post index_path, mail_template: template_create_payload

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(user) { json_post index_path, mail_template: template_create_payload }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to create a template' do
      payload = template_create_payload
      as(admin) { json_post index_path, mail_template: payload }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(template_obj['name']).to eq(payload[:name])
      expect(template_obj['label']).to eq(payload[:label])
      expect(template_obj['template_id']).to eq(payload[:template_id])
      expect(template_obj['user_visibility']).to eq(payload[:user_visibility])

      created = MailTemplate.find_by!(name: payload[:name])
      expect(created.label).to eq(payload[:label])
      expect(created.template_id).to eq(payload[:template_id])
      expect(created.user_visibility).to eq(payload[:user_visibility])
    end

    it 'validates presence of name' do
      as(admin) { json_post index_path, mail_template: template_create_payload.except(:name) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys).to include('name')
    end

    it 'validates presence of label' do
      as(admin) { json_post index_path, mail_template: template_create_payload.except(:label) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys).to include('label')
    end

    it 'validates presence of template_id' do
      as(admin) { json_post index_path, mail_template: template_create_payload.except(:template_id) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys).to include('template_id')
    end

    it 'validates user_visibility choices' do
      as(admin) { json_post index_path, mail_template: template_create_payload.merge(user_visibility: 'nope') }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys).to include('user_visibility')
    end

    it 'validates name uniqueness' do
      as(admin) { json_post index_path, mail_template: template_create_payload.merge(name: tpl_a.name) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys).to include('name')
    end
  end

  describe 'Update' do
    it 'rejects unauthenticated access' do
      json_put show_path(tpl_a.id), mail_template: { label: 'Changed' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(user) { json_put show_path(tpl_a.id), mail_template: { label: 'Changed' } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to update a template' do
      as(admin) { json_put show_path(tpl_a.id), mail_template: { label: 'Changed', user_visibility: 'visible' } }

      expect_status(200)
      expect(json['status']).to be(true)

      tpl_a.reload
      expect(tpl_a.label).to eq('Changed')
      expect(tpl_a.user_visibility).to eq('visible')
    end

    it 'validates user_visibility choices' do
      as(admin) { json_put show_path(tpl_a.id), mail_template: { user_visibility: 'nope' } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys).to include('user_visibility')
    end

    it 'validates name uniqueness' do
      as(admin) { json_put show_path(tpl_b.id), mail_template: { name: tpl_a.name } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys).to include('name')
    end

    it 'returns 404 for unknown template' do
      missing = MailTemplate.maximum(:id).to_i + 100

      as(admin) { json_put show_path(missing), mail_template: { label: 'Changed' } }

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
      tpl_del = MailTemplate.create!(
        name: 'spec_tpl_del',
        label: 'Spec Template Delete',
        template_id: 'daily_report',
        user_visibility: :default
      )

      MailTemplateTranslation.create!(
        mail_template: tpl_del,
        language: lang_en,
        from: 'noreply@example.test',
        subject: 'Spec Delete subject',
        text_plain: 'Delete me'
      )

      MailTemplateRecipient.create!(mail_template: tpl_del, mail_recipient: recp_a)

      as(admin) { json_delete show_path(tpl_del.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(MailTemplate.where(id: tpl_del.id)).to be_empty
      expect(MailTemplateTranslation.where(mail_template_id: tpl_del.id)).to be_empty
      expect(MailTemplateRecipient.where(mail_template_id: tpl_del.id)).to be_empty
    end

    it 'returns 404 for unknown template' do
      missing = MailTemplate.maximum(:id).to_i + 100

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

      ids = recipients_list.map { |row| rid(row['mail_recipient']) }
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
      expect(rid(recipient_obj['mail_recipient'])).to eq(recp_a.id)
    end

    it 'returns 404 for recipients not linked to template' do
      as(admin) { json_get recipient_path(tpl_b.id, recp_a.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'returns 404 for unknown template' do
      missing = MailTemplate.maximum(:id).to_i + 100

      as(admin) { json_get recipient_path(missing, recp_a.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'returns 404 for unknown recipient' do
      missing = MailRecipient.maximum(:id).to_i + 100

      as(admin) { json_get recipient_path(tpl_a.id, missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Recipient Create' do
    it 'rejects unauthenticated access' do
      json_post recipients_path(tpl_b.id), recipient: { mail_recipient: recp_a.id }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(user) { json_post recipients_path(tpl_b.id), recipient: { mail_recipient: recp_a.id } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to create a recipient join' do
      as(admin) { json_post recipients_path(tpl_b.id), recipient: { mail_recipient: recp_a.id } }

      expect_status(200)
      expect(json['status']).to be(true)
      MailTemplateRecipient.find_by!(mail_template: tpl_b, mail_recipient: recp_a)
    end

    it 'validates presence of mail_recipient' do
      as(admin) { json_post recipients_path(tpl_b.id), recipient: {} }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys).to include('mail_recipient')
    end

    it 'validates uniqueness of mail_recipient per template' do
      as(admin) { json_post recipients_path(tpl_a.id), recipient: { mail_recipient: recp_a.id } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys).to include('mail_recipient')
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
      expect(MailTemplateRecipient.where(mail_template: tpl_a, mail_recipient: recp_a)).to be_empty
    end

    it 'returns 404 for unknown recipient join' do
      as(admin) { json_delete recipient_path(tpl_b.id, recp_a.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Translation Index' do
    it 'rejects unauthenticated access' do
      json_get translations_path(tpl_a.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(user) { json_get translations_path(tpl_a.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'lists translations for admin users' do
      as(admin) { json_get translations_path(tpl_a.id) }

      expect_status(200)
      expect(json['status']).to be(true)

      ids = translations_list.map { |row| row['id'] }
      expect(ids).to include(tr_en.id, tr_cs.id)
    end

    it 'returns total_count meta when requested' do
      as(admin) { json_get translations_path(tpl_a.id), _meta: { count: true } }

      expect_status(200)
      expect(json.dig('response', '_meta', 'total_count')).to eq(tpl_a.mail_template_translations.count)
    end

    it 'supports limit pagination' do
      as(admin) { json_get translations_path(tpl_a.id), translation: { limit: 1 } }

      expect_status(200)
      expect(translations_list.length).to eq(1)
    end

    it 'supports from_id pagination' do
      boundary = [tr_en.id, tr_cs.id].min
      as(admin) { json_get translations_path(tpl_a.id), translation: { from_id: boundary } }

      expect_status(200)
      ids = translations_list.map { |row| row['id'] }
      expect(ids).to all(be > boundary)
    end
  end

  describe 'Translation Show' do
    it 'rejects unauthenticated access' do
      json_get translation_path(tpl_a.id, tr_en.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(user) { json_get translation_path(tpl_a.id, tr_en.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'shows a translation for admin users' do
      as(admin) { json_get translation_path(tpl_a.id, tr_en.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(rid(translation_obj['language'])).to eq(lang_en.id)
      expect(translation_obj['subject']).to eq(tr_en.subject)
    end

    it 'returns 404 for wrong template' do
      as(admin) { json_get translation_path(tpl_b.id, tr_en.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'returns 404 for unknown translation' do
      missing = MailTemplateTranslation.maximum(:id).to_i + 100

      as(admin) { json_get translation_path(tpl_a.id, missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Translation Create' do
    it 'rejects unauthenticated access' do
      json_post translations_path(tpl_b.id), translation: translation_create_payload

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(user) { json_post translations_path(tpl_b.id), translation: translation_create_payload }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to create a translation' do
      as(admin) { json_post translations_path(tpl_b.id), translation: translation_create_payload }

      expect_status(200)
      expect(json['status']).to be(true)
      MailTemplateTranslation.find_by!(mail_template: tpl_b, language: lang_en)
    end

    it 'validates presence of language' do
      as(admin) { json_post translations_path(tpl_b.id), translation: translation_create_payload.except(:language) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys).to include('language')
    end

    it 'validates presence of from' do
      as(admin) { json_post translations_path(tpl_b.id), translation: translation_create_payload.except(:from) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys).to include('from')
    end

    it 'validates presence of subject' do
      as(admin) { json_post translations_path(tpl_b.id), translation: translation_create_payload.except(:subject) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys).to include('subject')
    end

    it 'validates uniqueness of language per template' do
      as(admin) { json_post translations_path(tpl_a.id), translation: translation_create_payload.merge(language: lang_en.id) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys).to include('language')
    end
  end

  describe 'Translation Update' do
    it 'rejects unauthenticated access' do
      json_put translation_path(tpl_a.id, tr_en.id), translation: { subject: 'Updated subject' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(user) { json_put translation_path(tpl_a.id, tr_en.id), translation: { subject: 'Updated subject' } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to update a translation' do
      as(admin) { json_put translation_path(tpl_a.id, tr_en.id), translation: { subject: 'Updated subject', text_plain: 'Updated text' } }

      expect_status(200)
      expect(json['status']).to be(true)

      tr_en.reload
      expect(tr_en.subject).to eq('Updated subject')
      expect(tr_en.text_plain).to eq('Updated text')
    end

    it 'validates presence of subject' do
      as(admin) { json_put translation_path(tpl_a.id, tr_en.id), translation: { subject: '' } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys).to include('subject')
    end

    it 'returns 404 for unknown translation' do
      missing = MailTemplateTranslation.maximum(:id).to_i + 100

      as(admin) { json_put translation_path(tpl_a.id, missing), translation: { subject: 'Updated subject' } }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'returns 404 for wrong template' do
      as(admin) { json_put translation_path(tpl_b.id, tr_en.id), translation: { subject: 'Updated subject' } }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Translation Delete' do
    it 'rejects unauthenticated access' do
      json_delete translation_path(tpl_a.id, tr_en.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(user) { json_delete translation_path(tpl_a.id, tr_en.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to delete a translation' do
      as(admin) { json_delete translation_path(tpl_a.id, tr_en.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(MailTemplateTranslation.where(id: tr_en.id)).to be_empty
    end

    it 'returns 404 for unknown translation' do
      missing = MailTemplateTranslation.maximum(:id).to_i + 100

      as(admin) { json_delete translation_path(tpl_a.id, missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end
end
