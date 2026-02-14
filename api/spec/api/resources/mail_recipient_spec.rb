# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::MailRecipient' do
  let!(:recipient_a) do
    MailRecipient.create!(
      label: 'Spec Recipient A',
      to: 'a@test.invalid',
      cc: nil,
      bcc: nil
    )
  end

  let!(:recipient_b) do
    MailRecipient.create!(
      label: 'Spec Recipient B',
      to: nil,
      cc: 'cc@test.invalid',
      bcc: 'bcc@test.invalid'
    )
  end

  before do
    header 'Accept', 'application/json'
  end

  def index_path
    vpath('/mail_recipients')
  end

  def show_path(id)
    vpath("/mail_recipients/#{id}")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def json_post(path, payload)
    post path, JSON.dump(payload), { 'CONTENT_TYPE' => 'application/json' }
  end

  def json_put(path, payload)
    put path, JSON.dump(payload), { 'CONTENT_TYPE' => 'application/json' }
  end

  def json_delete(path)
    delete path, nil, { 'CONTENT_TYPE' => 'application/json' }
  end

  def recipients
    json.dig('response', 'mail_recipients')
  end

  def recipient
    json.dig('response', 'mail_recipient') || json['response']
  end

  def response_errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  describe 'API description' do
    it 'includes mail_recipient endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)

      expect(scopes).to include(
        'mail_recipient#index',
        'mail_recipient#show',
        'mail_recipient#create',
        'mail_recipient#update',
        'mail_recipient#delete'
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
      as(SpecSeed.user) { json_get index_path }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_get index_path }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to list mail recipients' do
      as(SpecSeed.admin) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(recipients).to be_a(Array)

      ids = recipients.map { |row| row['id'] }
      expect(ids).to include(recipient_a.id, recipient_b.id)

      row = recipients.detect { |item| item['id'] == recipient_a.id }
      expect(row).to include('id', 'label', 'to', 'cc', 'bcc')
    end

    it 'supports pagination limit' do
      as(SpecSeed.admin) { json_get index_path, mail_recipient: { limit: 1 } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(recipients.length).to eq(1)
    end

    it 'supports pagination from_id' do
      boundary = MailRecipient.order(:id).first.id

      as(SpecSeed.admin) { json_get index_path, mail_recipient: { from_id: boundary } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(recipients.map { |row| row['id'] }).to all(be > boundary)
    end

    it 'returns meta count' do
      as(SpecSeed.admin) { json_get index_path, _meta: { count: true } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(json.dig('response', '_meta', 'total_count')).to eq(MailRecipient.count)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path(recipient_a.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_get show_path(recipient_a.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to show a mail recipient' do
      as(SpecSeed.admin) { json_get show_path(recipient_a.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(recipient['id']).to eq(recipient_a.id)
      expect(recipient['label']).to eq(recipient_a.label)
      expect(recipient['to']).to eq(recipient_a.to)
      expect(recipient['cc']).to eq(recipient_a.cc)
      expect(recipient['bcc']).to eq(recipient_a.bcc)
    end

    it 'returns 404 for unknown mail recipients' do
      missing = MailRecipient.maximum(:id).to_i + 100

      as(SpecSeed.admin) { json_get show_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Create' do
    let(:payload) do
      {
        label: 'Spec Recipient New',
        to: 'new@test.invalid',
        cc: 'ncc@test.invalid',
        bcc: nil
      }
    end

    it 'rejects unauthenticated access' do
      json_post index_path, mail_recipient: payload

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_post index_path, mail_recipient: payload }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to create a mail recipient' do
      expect do
        as(SpecSeed.admin) { json_post index_path, mail_recipient: payload }
      end.to change(MailRecipient, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)
      expect(recipient).to be_a(Hash)
      expect(recipient['label']).to eq(payload[:label])
      expect(recipient['to']).to eq(payload[:to])
      expect(recipient['cc']).to eq(payload[:cc])
      expect(recipient['bcc']).to eq(payload[:bcc])

      record = MailRecipient.find(recipient['id'])
      expect(record.label).to eq(payload[:label])
      expect(record.to).to eq(payload[:to])
      expect(record.cc).to eq(payload[:cc])
      expect(record.bcc).to eq(payload[:bcc])
    end

    it 'returns validation errors for missing label' do
      expect do
        as(SpecSeed.admin) { json_post index_path, mail_recipient: payload.except(:label) }
      end.not_to change(MailRecipient, :count)

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('label')
    end
  end

  describe 'Update' do
    it 'rejects unauthenticated access' do
      json_put show_path(recipient_a.id), mail_recipient: { label: 'Changed', to: nil }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_put show_path(recipient_a.id), mail_recipient: { label: 'Changed', to: nil } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to update a mail recipient' do
      as(SpecSeed.admin) { json_put show_path(recipient_a.id), mail_recipient: { label: 'Changed', to: nil } }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(recipient_a.reload.label).to eq('Changed')
      expect(recipient_a.to).to be_nil
    end

    it 'returns validation errors for blank label' do
      original_label = recipient_a.label

      as(SpecSeed.admin) { json_put show_path(recipient_a.id), mail_recipient: { label: '' } }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors.keys.map(&:to_s)).to include('label')
      expect(recipient_a.reload.label).to eq(original_label)
    end

    it 'returns 404 for unknown mail recipients' do
      missing = MailRecipient.maximum(:id).to_i + 100

      as(SpecSeed.admin) { json_put show_path(missing), mail_recipient: { label: 'Changed' } }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Delete' do
    let!(:to_delete) do
      MailRecipient.create!(
        label: 'Spec Recipient Delete',
        to: 'del@test.invalid',
        cc: nil,
        bcc: nil
      )
    end

    it 'rejects unauthenticated access' do
      json_delete show_path(to_delete.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_delete show_path(to_delete.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to delete a mail recipient' do
      expect do
        as(SpecSeed.admin) { json_delete show_path(to_delete.id) }
      end.to change(MailRecipient, :count).by(-1)

      expect_status(200)
      expect(json['status']).to be(true)
      expect(MailRecipient.find_by(id: to_delete.id)).to be_nil
    end

    it 'returns 404 for unknown mail recipients' do
      missing = MailRecipient.maximum(:id).to_i + 100

      as(SpecSeed.admin) { json_delete show_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end
end
