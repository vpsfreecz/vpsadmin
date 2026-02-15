# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::User::MailRoleRecipient' do
  before do
    header 'Accept', 'application/json'
  end

  def index_path(user_id)
    vpath("/users/#{user_id}/mail_role_recipients")
  end

  def show_path(user_id, role)
    vpath("/users/#{user_id}/mail_role_recipients/#{role}")
  end

  def update_path(user_id, role)
    vpath("/users/#{user_id}/mail_role_recipients/#{role}")
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

  def recipients
    json.dig('response', 'mail_role_recipients') || []
  end

  def recipient
    json.dig('response', 'mail_role_recipient') || json['response']
  end

  def response_errors
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

  describe 'API description' do
    it 'includes mail role recipient endpoints' do
      scopes = EndpointInventory.scopes_for_version(self, api_version)
      expect(scopes).to include(
        'user.mail_role_recipient#index',
        'user.mail_role_recipient#show',
        'user.mail_role_recipient#update'
      )
    end
  end

  describe 'Index' do
    it 'rejects unauthenticated access' do
      json_get index_path(SpecSeed.user.id)

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows user to list their own role recipients' do
      UserMailRoleRecipient.where(user: SpecSeed.user).delete_all

      as(SpecSeed.user) { json_get index_path(SpecSeed.user.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(recipients).to be_a(Array)

      roles = recipients.map { |row| row['id'] }
      expect(roles).to include('account', 'admin')

      account_row = recipients.find { |row| row['id'] == 'account' }
      admin_row = recipients.find { |row| row['id'] == 'admin' }

      expect(account_row).to include('id', 'label', 'description', 'to')
      expect(account_row['label']).to eq('Account management')
      expect(account_row['to']).to be_nil

      expect(admin_row).to include('id', 'label', 'description', 'to')
      expect(admin_row['label']).to eq('System administrator')
      expect(admin_row['to']).to be_nil

      expect(roles.index('account')).to be < roles.index('admin')
    end

    it 'denies user listing another user recipients' do
      as(SpecSeed.user) { json_get index_path(SpecSeed.other_user.id) }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to match(/access denied/i)
    end

    it 'allows admin listing another user recipients' do
      UserMailRoleRecipient.where(user: SpecSeed.other_user).delete_all

      as(SpecSeed.admin) { json_get index_path(SpecSeed.other_user.id) }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(recipients.map { |row| row['id'] }).to include('account', 'admin')
    end
  end

  describe 'Show' do
    it 'rejects unauthenticated access' do
      json_get show_path(SpecSeed.user.id, 'account')

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'returns 404 when no record exists for that role' do
      UserMailRoleRecipient.where(user: SpecSeed.user, role: 'admin').delete_all

      as(SpecSeed.user) { json_get show_path(SpecSeed.user.id, 'admin') }

      expect_status(404)
      expect(json['status']).to be(false)
    end

    it 'shows an existing configured recipient' do
      UserMailRoleRecipient.where(user: SpecSeed.user, role: 'account').delete_all
      UserMailRoleRecipient.create!(user: SpecSeed.user, role: 'account', to: 'acct@test.invalid')

      as(SpecSeed.user) { json_get show_path(SpecSeed.user.id, 'account') }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(recipient['id']).to eq('account')
      expect(recipient['label']).to eq('Account management')
      expect(recipient['to']).to eq('acct@test.invalid')
    end

    it 'denies user showing another user recipient' do
      UserMailRoleRecipient.where(user: SpecSeed.other_user, role: 'account').delete_all
      UserMailRoleRecipient.create!(user: SpecSeed.other_user, role: 'account', to: 'other@test.invalid')

      as(SpecSeed.user) { json_get show_path(SpecSeed.other_user.id, 'account') }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to match(/access denied/i)
    end

    it 'allows admin to show another user recipient' do
      UserMailRoleRecipient.where(user: SpecSeed.other_user, role: 'account').delete_all
      UserMailRoleRecipient.create!(user: SpecSeed.other_user, role: 'account', to: 'other@test.invalid')

      as(SpecSeed.admin) { json_get show_path(SpecSeed.other_user.id, 'account') }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(recipient['id']).to eq('account')
      expect(recipient['to']).to eq('other@test.invalid')
    end
  end

  describe 'Update' do
    it 'rejects unauthenticated access' do
      json_put update_path(SpecSeed.user.id, 'account'),
               mail_role_recipient: { to: 'x@test.invalid' }

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'allows user to create/update their own recipient' do
      UserMailRoleRecipient.where(user: SpecSeed.user, role: 'account').delete_all

      as(SpecSeed.user) do
        json_put update_path(SpecSeed.user.id, 'account'),
                 mail_role_recipient: { to: "a@test.invalid, b@test.invalid \n" }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(recipient['id']).to eq('account')
      expect(recipient['to']).to eq('a@test.invalid,b@test.invalid')

      recp = UserMailRoleRecipient.find_by!(user: SpecSeed.user, role: 'account')
      expect(recp.to).to eq('a@test.invalid,b@test.invalid')
    end

    it 'allows user to clear recipient by sending empty string' do
      UserMailRoleRecipient.where(user: SpecSeed.user, role: 'account').delete_all
      UserMailRoleRecipient.create!(user: SpecSeed.user, role: 'account', to: 'acct@test.invalid')

      as(SpecSeed.user) do
        json_put update_path(SpecSeed.user.id, 'account'),
                 mail_role_recipient: { to: '' }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(recipient['id']).to eq('account')
      expect(recipient['to']).to be_nil
      expect(UserMailRoleRecipient.where(user: SpecSeed.user, role: 'account')).to be_empty
    end

    it 'rejects invalid email address' do
      UserMailRoleRecipient.where(user: SpecSeed.user, role: 'account').delete_all

      as(SpecSeed.user) do
        json_put update_path(SpecSeed.user.id, 'account'),
                 mail_role_recipient: { to: 'notanemail' }
      end

      expect_status(200)
      expect(json['status']).to be(false)

      errors = response_errors
      expect(errors.keys.map(&:to_s)).to include('to')

      messages = Array(errors['to'] || errors[:to]).join(' ')
      expect(messages).to match(/not a valid e-mail address/i)
    end

    it 'denies updating another user recipient' do
      UserMailRoleRecipient.where(user: SpecSeed.other_user, role: 'account').delete_all

      as(SpecSeed.user) do
        json_put update_path(SpecSeed.other_user.id, 'account'),
                 mail_role_recipient: { to: 'x@test.invalid' }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message).to match(/access denied/i)
      expect(UserMailRoleRecipient.where(user: SpecSeed.other_user, role: 'account')).to be_empty
    end

    it 'allows admin to update another user recipient' do
      UserMailRoleRecipient.where(user: SpecSeed.other_user, role: 'account').delete_all

      as(SpecSeed.admin) do
        json_put update_path(SpecSeed.other_user.id, 'account'),
                 mail_role_recipient: { to: 'admin@test.invalid' }
      end

      expect_status(200)
      expect(json['status']).to be(true)
      expect(recipient['id']).to eq('account')
      expect(recipient['to']).to eq('admin@test.invalid')

      recp = UserMailRoleRecipient.find_by!(user: SpecSeed.other_user, role: 'account')
      expect(recp.to).to eq('admin@test.invalid')
    end
  end
end
