# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::MailLog' do
  before do
    header 'Accept', 'application/json'
    SpecSeed.admin
    SpecSeed.user
    SpecSeed.support
    SpecSeed.other_user

    template
    28.times do |i|
      create_mail_log!(
        user: SpecSeed.user,
        mail_template: template,
        subject: "Bulk #{i}",
        text_plain: "bulk #{i}",
        text_html: "<p>bulk #{i}</p>"
      )
    end
  end

  def index_path
    vpath('/mail_logs')
  end

  def show_path(id)
    vpath("/mail_logs/#{id}")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def mail_logs
    json.dig('response', 'mail_logs') || []
  end

  def mail_log
    json.dig('response', 'mail_log')
  end

  def rid(value)
    value.is_a?(Hash) ? value['id'] : value
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def create_template!(name: 'spec_tpl', label: 'Spec Template', template_id: 'spec.template', user_visibility: :default)
    MailTemplate.create!(
      name: name,
      label: label,
      template_id: template_id,
      user_visibility: user_visibility
    )
  end

  def create_mail_log!(user:, mail_template:, to: 'to@example.test', cc: '', bcc: '', from: 'from@example.test',
                       subject: 'Spec subject', text_plain: 'plain', text_html: '<p>html</p>',
                       reply_to: nil, return_path: nil, message_id: nil, in_reply_to: nil, references: nil)
    MailLog.create!(
      user: user,
      mail_template: mail_template,
      to: to,
      cc: cc,
      bcc: bcc,
      from: from,
      subject: subject,
      text_plain: text_plain,
      text_html: text_html,
      reply_to: reply_to,
      return_path: return_path,
      message_id: message_id,
      in_reply_to: in_reply_to,
      references: references
    )
  end

  let!(:template) { create_template!(name: 'spec_tpl_a') }

  let!(:log_a) do
    create_mail_log!(
      user: SpecSeed.user,
      mail_template: template,
      subject: 'Mail A',
      reply_to: 'reply@example.test',
      return_path: 'bounce@example.test',
      message_id: '<msg-a@example.test>',
      in_reply_to: '<parent@example.test>',
      references: '<ref1@example.test> <ref2@example.test>',
      text_plain: 'hello',
      text_html: '<p>hello</p>'
    )
  end

  let!(:log_b) do
    create_mail_log!(
      user: SpecSeed.other_user,
      mail_template: template,
      subject: 'Mail B',
      text_plain: 'b',
      text_html: '<p>b</p>'
    )
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids non-admin users' do
      as(SpecSeed.user) { json_get index_path }

      expect_status(403)
      expect(json['status']).to be(false)

      as(SpecSeed.support) { json_get index_path }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to list mail logs' do
      as(SpecSeed.admin) { json_get index_path, mail_log: { limit: 100 } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(mail_logs).to be_an(Array)
      expect(mail_logs).not_to be_empty

      row = mail_logs.find { |item| item['id'] == log_a.id }
      expect(row).not_to be_nil
      expect(row).to include(
        'id',
        'user',
        'to',
        'cc',
        'bcc',
        'from',
        'subject',
        'text_plain',
        'text_html',
        'reply_to',
        'return_path',
        'message_id',
        'in_reply_to',
        'references',
        'mail_template',
        'created_at'
      )
      expect(rid(row['user'])).to eq(SpecSeed.user.id)
      expect(rid(row['mail_template'])).to eq(template.id)

      other_row = mail_logs.find { |item| item['id'] == log_b.id }
      expect(other_row).not_to be_nil
      expect(rid(other_row['user'])).to eq(SpecSeed.other_user.id)
    end

    it 'uses default limit of 25' do
      as(SpecSeed.admin) { json_get index_path }

      expect_status(200)
      expect(mail_logs.length).to eq(25)
      returned_ids = mail_logs.map { |item| item['id'] }
      all_ids = MailLog.pluck(:id)
      expect(returned_ids - all_ids).to be_empty
    end

    it 'supports explicit limit' do
      as(SpecSeed.admin) { json_get index_path, mail_log: { limit: 1 } }

      expect_status(200)
      expect(mail_logs.length).to eq(1)
    end

    it 'supports from_id pagination' do
      boundary = MailLog.order(:id).first.id

      as(SpecSeed.admin) { json_get index_path, mail_log: { from_id: boundary } }

      expect_status(200)
      returned_ids = mail_logs.map { |item| item['id'] }
      expect(returned_ids).not_to be_empty
      expect(returned_ids).to all(be > boundary)
    end

    it 'returns total_count meta when requested' do
      as(SpecSeed.admin) { json_get index_path, _meta: { count: true } }

      expect_status(200)
      expect(json.dig('response', '_meta', 'total_count')).to eq(MailLog.count)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path(log_a.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids non-admin users' do
      as(SpecSeed.user) { json_get show_path(log_a.id) }

      expect_status(403)
      expect(json['status']).to be(false)

      as(SpecSeed.support) { json_get show_path(log_a.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to view a mail log' do
      as(SpecSeed.admin) { json_get show_path(log_a.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(mail_log['id']).to eq(log_a.id)
      expect(mail_log['subject']).to eq('Mail A')
      expect(mail_log['text_plain']).to eq('hello')
      expect(mail_log['text_html']).to eq('<p>hello</p>')
      expect(rid(mail_log['user'])).to eq(SpecSeed.user.id)
      expect(rid(mail_log['mail_template'])).to eq(template.id)
      expect(mail_log['reply_to']).to eq('reply@example.test')
      expect(mail_log['return_path']).to eq('bounce@example.test')
      expect(mail_log['message_id']).to eq('<msg-a@example.test>')
      expect(mail_log['in_reply_to']).to eq('<parent@example.test>')
      expect(mail_log['references']).to include('<ref1@example.test>', '<ref2@example.test>')
    end

    it 'returns 404 for unknown id' do
      missing = MailLog.maximum(:id).to_i + 100

      as(SpecSeed.admin) { json_get show_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end
end
