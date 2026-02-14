# frozen_string_literal: true

require 'securerandom'

RSpec.describe 'VpsAdmin::API::Resources::Mailbox' do
  before do
    header 'Accept', 'application/json'
    SpecSeed.admin
    SpecSeed.user
    SpecSeed.support
  end

  def index_path
    vpath('/mailboxes')
  end

  def show_path(id)
    vpath("/mailboxes/#{id}")
  end

  def handlers_index_path(mailbox_id)
    vpath("/mailboxes/#{mailbox_id}/handler")
  end

  def handler_path(mailbox_id, handler_id)
    vpath("/mailboxes/#{mailbox_id}/handler/#{handler_id}")
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

  def mailboxes
    json.dig('response', 'mailboxes') || []
  end

  def mailbox_obj
    json.dig('response', 'mailbox') || json['response']
  end

  def handlers
    json.dig('response', 'handlers') || json.dig('response', 'mailbox_handlers') || []
  end

  def handler_obj
    json.dig('response', 'handler') || json.dig('response', 'mailbox_handler') || json['response']
  end

  def errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def msg
    json['message'] || json.dig('response', 'message') || json['error']
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected #{code} for #{path}, got #{last_response.status}: #{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  let!(:mailbox_a) do
    Mailbox.create!(
      label: 'Spec Mailbox A',
      server: 'imap-a.example.test',
      port: 993,
      user: 'user-a',
      password: 'pw-a',
      enable_ssl: true
    )
  end

  let!(:mailbox_b) do
    Mailbox.create!(
      label: 'Spec Mailbox B',
      server: 'imap-b.example.test',
      port: 993,
      user: 'user-b',
      password: 'pw-b',
      enable_ssl: false
    )
  end

  let!(:handler_a_secondary) do
    MailboxHandler.create!(
      mailbox: mailbox_a,
      class_name: 'Spec::HandlerA2',
      order: 2,
      continue: false
    )
  end

  let!(:handler_a_primary) do
    MailboxHandler.create!(
      mailbox: mailbox_a,
      class_name: 'Spec::HandlerA1',
      order: 1,
      continue: true
    )
  end

  let!(:handler_b1) do
    MailboxHandler.create!(
      mailbox: mailbox_b,
      class_name: 'Spec::HandlerB1',
      order: 1,
      continue: false
    )
  end

  describe 'API description' do
    it 'includes mailbox scopes' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)
      expect(scopes).to include(
        'mailbox#index', 'mailbox#show', 'mailbox#create', 'mailbox#update', 'mailbox#delete',
        'mailbox.handler#index', 'mailbox.handler#show', 'mailbox.handler#create', 'mailbox.handler#update',
        'mailbox.handler#delete'
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

    it 'allows admin to list mailboxes' do
      as(SpecSeed.admin) { json_get index_path }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(mailboxes).to be_an(Array)

      ids = mailboxes.map { |row| row['id'] }
      expect(ids).to include(mailbox_a.id, mailbox_b.id)

      row = mailboxes.find { |item| item['id'] == mailbox_a.id }
      expect(row).to include('id', 'label', 'server', 'port', 'user', 'enable_ssl', 'created_at', 'updated_at')
      expect(row).not_to have_key('password')
    end

    it 'supports pagination limit' do
      as(SpecSeed.admin) { json_get index_path, mailbox: { limit: 1 } }

      expect_status(200)
      expect(mailboxes.length).to eq(1)
    end

    it 'supports pagination from_id' do
      boundary = Mailbox.order(:id).first.id
      as(SpecSeed.admin) { json_get index_path, mailbox: { from_id: boundary } }

      expect_status(200)
      ids = mailboxes.map { |row| row['id'] }
      expect(ids).to all(be > boundary)
    end

    it 'returns meta count' do
      as(SpecSeed.admin) { json_get index_path, _meta: { count: true } }

      expect_status(200)
      expect(json.dig('response', '_meta', 'total_count')).to eq(Mailbox.count)
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path(mailbox_a.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_get show_path(mailbox_a.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_get show_path(mailbox_a.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admins to show any mailbox' do
      as(SpecSeed.admin) { json_get show_path(mailbox_a.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(mailbox_obj).to include('id', 'label', 'server', 'port', 'user', 'enable_ssl', 'created_at', 'updated_at')
      expect(mailbox_obj).not_to have_key('password')
    end

    it 'returns 404 for unknown mailbox' do
      missing = Mailbox.maximum(:id).to_i + 100
      as(SpecSeed.admin) { json_get show_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Create' do
    it 'rejects unauthenticated access' do
      json_post index_path, mailbox: { label: 'Spec', server: 'imap.test', user: 'user', password: 'pass' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) do
        json_post index_path, mailbox: { label: 'Spec', server: 'imap.test', user: 'user', password: 'pass' }
      end

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) do
        json_post index_path, mailbox: { label: 'Spec', server: 'imap.test', user: 'user', password: 'pass' }
      end

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admins to create a mailbox' do
      token = SecureRandom.hex(4)
      payload = {
        label: "Spec Mailbox #{token}",
        server: "imap-#{token}.example.test",
        user: "user-#{token}",
        password: "pw-#{token}",
        port: 143,
        enable_ssl: false
      }

      expect do
        as(SpecSeed.admin) { json_post index_path, mailbox: payload }
      end.to change(Mailbox, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)
      expect(mailbox_obj).to be_a(Hash)
      expect(mailbox_obj['label']).to eq(payload[:label])
      expect(mailbox_obj).not_to have_key('password')

      record = Mailbox.find(mailbox_obj['id'])
      expect(record.password).to eq(payload[:password])
    end

    it 'uses defaults for port and enable_ssl' do
      token = SecureRandom.hex(4)
      payload = {
        label: "Spec Mailbox Defaults #{token}",
        server: "imap-defaults-#{token}.example.test",
        user: "user-defaults-#{token}",
        password: "pw-defaults-#{token}"
      }

      expect do
        as(SpecSeed.admin) { json_post index_path, mailbox: payload }
      end.to change(Mailbox, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)

      record = Mailbox.find(mailbox_obj['id'])
      expect(record.enable_ssl).to be(true)
      expect(record.port).to eq(993)
    end

    it 'returns validation errors for missing label' do
      token = SecureRandom.hex(4)
      payload = {
        server: "imap-#{token}.example.test",
        user: "user-#{token}",
        password: "pw-#{token}"
      }

      as(SpecSeed.admin) { json_post index_path, mailbox: payload }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('label')
    end

    it 'returns validation errors for missing server' do
      token = SecureRandom.hex(4)
      payload = {
        label: "Spec Mailbox #{token}",
        user: "user-#{token}",
        password: "pw-#{token}"
      }

      as(SpecSeed.admin) { json_post index_path, mailbox: payload }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('server')
    end

    it 'returns validation errors for missing user' do
      token = SecureRandom.hex(4)
      payload = {
        label: "Spec Mailbox #{token}",
        server: "imap-#{token}.example.test",
        password: "pw-#{token}"
      }

      as(SpecSeed.admin) { json_post index_path, mailbox: payload }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('user')
    end

    it 'returns validation errors for missing password' do
      token = SecureRandom.hex(4)
      payload = {
        label: "Spec Mailbox #{token}",
        server: "imap-#{token}.example.test",
        user: "user-#{token}"
      }

      as(SpecSeed.admin) { json_post index_path, mailbox: payload }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('password')
    end
  end

  describe 'Update' do
    it 'rejects unauthenticated access' do
      json_put show_path(mailbox_a.id), mailbox: { label: 'Spec Updated' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_put show_path(mailbox_a.id), mailbox: { label: 'Spec Updated' } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_put show_path(mailbox_a.id), mailbox: { label: 'Spec Updated' } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admins to update a mailbox' do
      new_label = "Spec Mailbox Updated #{SecureRandom.hex(3)}"

      as(SpecSeed.admin) do
        json_put show_path(mailbox_a.id), mailbox: {
          label: new_label,
          enable_ssl: false
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(mailbox_obj).to be_a(Hash)
      expect(mailbox_obj['label']).to eq(new_label)
      expect(mailbox_obj['enable_ssl']).to be(false)

      mailbox_a.reload
      expect(mailbox_a.label).to eq(new_label)
      expect(mailbox_a.enable_ssl).to be(false)
    end

    it 'returns 404 for unknown mailbox' do
      missing = Mailbox.maximum(:id).to_i + 100
      as(SpecSeed.admin) { json_put show_path(missing), mailbox: { label: 'Spec Updated' } }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Delete' do
    it 'rejects unauthenticated access' do
      json_delete show_path(mailbox_a.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_delete show_path(mailbox_a.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_delete show_path(mailbox_a.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admins to delete a mailbox and its handlers' do
      mailbox = Mailbox.create!(
        label: 'Spec Mailbox Delete',
        server: 'imap-delete.example.test',
        port: 993,
        user: 'user-delete',
        password: 'pw-delete',
        enable_ssl: true
      )

      MailboxHandler.create!(
        mailbox: mailbox,
        class_name: 'Spec::DeleteHandler',
        order: 1,
        continue: false
      )

      expect do
        as(SpecSeed.admin) { json_delete show_path(mailbox.id) }
      end.to change(Mailbox, :count).by(-1)
         .and change(MailboxHandler, :count).by(-1)

      expect_status(200)
      expect(json['status']).to be(true)
      expect(MailboxHandler.where(mailbox_id: mailbox.id)).to be_empty
    end

    it 'returns 404 for unknown mailbox' do
      missing = Mailbox.maximum(:id).to_i + 100
      as(SpecSeed.admin) { json_delete show_path(missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Handler Index' do
    it 'rejects unauthenticated access' do
      json_get handlers_index_path(mailbox_a.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_get handlers_index_path(mailbox_a.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_get handlers_index_path(mailbox_a.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to list handlers' do
      as(SpecSeed.admin) { json_get handlers_index_path(mailbox_a.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(handlers).to be_an(Array)

      ids = handlers.map { |row| row['id'] }
      expect(ids).to include(handler_a_primary.id, handler_a_secondary.id)
      expect(ids).not_to include(handler_b1.id)
      expect(ids.index(handler_a_primary.id)).to be < ids.index(handler_a_secondary.id)

      row = handlers.find { |item| item['id'] == handler_a_primary.id }
      expect(row).to include('id', 'class_name', 'order', 'continue', 'created_at', 'updated_at')
    end

    it 'supports pagination limit' do
      as(SpecSeed.admin) { json_get handlers_index_path(mailbox_a.id), handler: { limit: 1 } }

      expect_status(200)
      expect(handlers.length).to eq(1)
    end

    it 'supports pagination from_id' do
      boundary = MailboxHandler.order(:id).first.id
      as(SpecSeed.admin) { json_get handlers_index_path(mailbox_a.id), handler: { from_id: boundary } }

      expect_status(200)
      ids = handlers.map { |row| row['id'] }
      expect(ids).to all(be > boundary)
    end
  end

  describe 'Handler Show' do
    it 'rejects unauthenticated access' do
      json_get handler_path(mailbox_a.id, handler_a_primary.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_get handler_path(mailbox_a.id, handler_a_primary.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_get handler_path(mailbox_a.id, handler_a_primary.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admins to show a mailbox handler' do
      as(SpecSeed.admin) { json_get handler_path(mailbox_a.id, handler_a_primary.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(handler_obj).to include('id', 'class_name', 'order', 'continue', 'created_at', 'updated_at')
      expect(handler_obj['id']).to eq(handler_a_primary.id)
    end

    it 'returns 404 for handlers belonging to another mailbox' do
      as(SpecSeed.admin) { json_get handler_path(mailbox_a.id, handler_b1.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'returns 404 for unknown handler' do
      missing = MailboxHandler.maximum(:id).to_i + 100
      as(SpecSeed.admin) { json_get handler_path(mailbox_a.id, missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Handler Create' do
    it 'rejects unauthenticated access' do
      json_post handlers_index_path(mailbox_a.id), handler: { class_name: 'Spec::NewHandler' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) do
        json_post handlers_index_path(mailbox_a.id), handler: { class_name: 'Spec::NewHandler' }
      end

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) do
        json_post handlers_index_path(mailbox_a.id), handler: { class_name: 'Spec::NewHandler' }
      end

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admins to create a handler' do
      token = SecureRandom.hex(4)
      payload = {
        class_name: "Spec::NewHandler#{token}",
        order: 5,
        continue: true
      }

      expect do
        as(SpecSeed.admin) { json_post handlers_index_path(mailbox_a.id), handler: payload }
      end.to change(MailboxHandler, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)
      expect(handler_obj).to be_a(Hash)
      expect(handler_obj['class_name']).to eq(payload[:class_name])

      record = MailboxHandler.find(handler_obj['id'])
      expect(record.mailbox_id).to eq(mailbox_a.id)
    end

    it 'uses defaults for order and continue' do
      token = SecureRandom.hex(4)
      payload = { class_name: "Spec::DefaultHandler#{token}" }

      expect do
        as(SpecSeed.admin) { json_post handlers_index_path(mailbox_a.id), handler: payload }
      end.to change(MailboxHandler, :count).by(1)

      expect_status(200)
      expect(json['status']).to be(true)

      record = MailboxHandler.find_by!(class_name: payload[:class_name])
      expect(record.order).to eq(1)
      expect(record.continue).to be(false)
    end

    it 'returns validation errors for missing class_name' do
      as(SpecSeed.admin) { json_post handlers_index_path(mailbox_a.id), handler: {} }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(errors.keys.map(&:to_s)).to include('class_name')
    end
  end

  describe 'Handler Update' do
    it 'rejects unauthenticated access' do
      json_put handler_path(mailbox_a.id, handler_a_primary.id), handler: { order: 10 }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_put handler_path(mailbox_a.id, handler_a_primary.id), handler: { order: 10 } }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) do
        json_put handler_path(mailbox_a.id, handler_a_primary.id), handler: { order: 10 }
      end

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admins to update handlers' do
      as(SpecSeed.admin) do
        json_put handler_path(mailbox_a.id, handler_a_primary.id), handler: {
          order: 10,
          continue: false
        }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(handler_obj).to be_a(Hash)
      expect(handler_obj['order']).to eq(10)
      expect(handler_obj['continue']).to be(false)

      handler_a_primary.reload
      expect(handler_a_primary.order).to eq(10)
      expect(handler_a_primary.continue).to be(false)
    end

    it 'returns 404 for handlers belonging to another mailbox' do
      as(SpecSeed.admin) do
        json_put handler_path(mailbox_a.id, handler_b1.id), handler: { order: 2 }
      end

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'returns 404 for unknown handler' do
      missing = MailboxHandler.maximum(:id).to_i + 100
      as(SpecSeed.admin) do
        json_put handler_path(mailbox_a.id, missing), handler: { order: 2 }
      end

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end

  describe 'Handler Delete' do
    it 'rejects unauthenticated access' do
      json_delete handler_path(mailbox_a.id, handler_a_secondary.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_delete handler_path(mailbox_a.id, handler_a_secondary.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_delete handler_path(mailbox_a.id, handler_a_secondary.id) }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admins to delete handlers' do
      expect do
        as(SpecSeed.admin) { json_delete handler_path(mailbox_a.id, handler_a_secondary.id) }
      end.to change(MailboxHandler, :count).by(-1)

      expect_status(200)
      expect(json['status']).to be(true)
    end

    it 'returns 404 for handlers belonging to another mailbox' do
      as(SpecSeed.admin) { json_delete handler_path(mailbox_a.id, handler_b1.id) }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'returns 404 for unknown handler' do
      missing = MailboxHandler.maximum(:id).to_i + 100
      as(SpecSeed.admin) { json_delete handler_path(mailbox_a.id, missing) }

      expect_status(404)
      expect(json['status']).to be(false)
    end
  end
end
