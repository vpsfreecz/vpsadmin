# frozen_string_literal: true

require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20260624121000_migrate_legacy_email_recipients_to_routes')

RSpec.describe MigrateLegacyEmailRecipientsToRoutes do
  def define_legacy_schema
    define_schema do
      create_table :users do |t|
        t.string :login, null: false
        t.string :email, null: false
        t.integer :level, null: false, default: 0
      end

      create_table :notification_templates do |t|
        t.string :name, null: false, limit: 100
        t.string :label, limit: 255
      end

      create_table :email_recipients, id: { type: :integer, unsigned: true } do |t|
        t.string :label, limit: 100, null: false
        t.string :to, limit: 500
        t.string :cc, limit: 500
        t.string :bcc, limit: 500
      end

      create_table :notification_template_email_recipients,
                   id: { type: :integer, unsigned: true } do |t|
        t.integer :notification_template_id, null: false
        t.integer :email_recipient_id, null: false
      end
      add_index :notification_template_email_recipients,
                %i[notification_template_id email_recipient_id],
                unique: true,
                name: :notification_template_email_recipients_unique

      create_table :user_notification_template_recipients,
                   id: { type: :integer, unsigned: true } do |t|
        t.integer :user_id, null: false
        t.integer :notification_template_id, null: false
        t.string :to, limit: 500
        t.boolean :enabled, null: false, default: true
      end

      create_table :user_email_role_recipients, id: { type: :integer, unsigned: true } do |t|
        t.integer :user_id, null: false
        t.string :role, limit: 100, null: false
        t.string :to, limit: 500
      end

      create_table :notification_receivers do |t|
        t.references :user, null: false
        t.string :label, null: false, limit: 255
        t.text :description
        t.boolean :enabled, null: false, default: true
        t.boolean :mute, null: false, default: false
        t.timestamps null: false
      end

      create_table :notification_targets do |t|
        t.references :user, null: false
        t.string :action, null: false, limit: 50
        t.string :label, limit: 255
        t.integer :target_kind, null: false, default: 0
        t.text :target_value
        t.string :identity_key, limit: 255
        t.boolean :enabled, null: false, default: true
        t.datetime :verified_at
        t.timestamps null: false
      end

      create_table :notification_receiver_targets do |t|
        t.references :notification_receiver, null: false
        t.references :notification_target, null: false
        t.integer :position, null: false, default: 0
        t.timestamps null: false
      end

      create_table :event_routes do |t|
        t.references :user, null: false
        t.bigint :parent_id
        t.bigint :notification_receiver_id
        t.string :label, limit: 255
        t.integer :position, null: false, default: 0
        t.boolean :enabled, null: false, default: true
        t.string :event_type, limit: 100
        t.string :event_type_pattern, limit: 100
        t.string :template_name, limit: 100
        t.integer :subject_scope, null: false, default: 0
        t.boolean :continue, null: false, default: false
        t.boolean :single_use, null: false, default: false
        t.datetime :spent_at
        t.datetime :expires_at
        t.bigint :hit_count, null: false, default: 0
        t.timestamps null: false
      end

      create_table :event_route_matchers do |t|
        t.references :event_route, null: false
        t.string :field, null: false, limit: 100
        t.string :operator, null: false, limit: 50
        t.text :value, null: false
        t.timestamps null: false
      end
    end
  end

  def seed_success_rows
    direct_admin_id = insert_row(:users, login: 'direct_admin', email: 'direct-admin@example.test', level: 90)
    custom_admin_id = insert_row(:users, login: 'custom_admin', email: 'custom-admin@example.test', level: 90)

    templates = {
      daily_report: insert_template('daily_report', 'Daily report for admins'),
      payments_overview: insert_template('payments_overview', 'Payments overview for admins'),
      user_suspend: insert_template('user_suspend', 'User account suspended'),
      expiration_user_active: insert_template('expiration_user_active', 'Payment notification'),
      expiration_vps_active: insert_template('expiration_vps_active', 'VPS payment notification'),
      request_resolve: insert_template('request_resolve_user_change_approved', 'Request approved'),
      alert: insert_template('alert_admin_monthly_traffic_confirmed', 'Monthly traffic alert')
    }

    default_recipient_id = insert_row(
      :email_recipients,
      label: 'direct_admin',
      to: 'direct-admin@example.test',
      cc: nil,
      bcc: nil
    )
    custom_recipient_id = insert_row(
      :email_recipients,
      label: 'custom_admin',
      to: nil,
      cc: nil,
      bcc: 'legacy-ops@example.test'
    )

    link_template(templates.fetch(:daily_report), default_recipient_id)
    link_template(templates.fetch(:payments_overview), custom_recipient_id)
    link_template(templates.fetch(:user_suspend), custom_recipient_id)
    link_template(templates.fetch(:expiration_user_active), custom_recipient_id)
    link_template(templates.fetch(:expiration_vps_active), default_recipient_id)
    link_template(templates.fetch(:request_resolve), default_recipient_id)
    link_template(templates.fetch(:alert), default_recipient_id)

    {
      direct_admin_id:,
      custom_admin_id:
    }
  end

  def insert_template(name, label)
    insert_row(:notification_templates, name:, label:)
  end

  def link_template(template_id, recipient_id)
    insert_row(
      :notification_template_email_recipients,
      notification_template_id: template_id,
      email_recipient_id: recipient_id
    )
  end

  def route_for(user_id:, event_type:, template_name:)
    find_row(
      :event_routes,
      user_id:,
      event_type:,
      template_name:,
      subject_scope: 1
    )
  end

  def expect_matcher(route, field, operator, value)
    expect(row_count(:event_route_matchers,
                     event_route_id: route.fetch('id'),
                     field:,
                     operator:,
                     value:)).to eq(1)
  end

  def expect_no_matcher(route, field)
    expect(row_count(:event_route_matchers,
                     event_route_id: route.fetch('id'),
                     field:)).to eq(0)
  end

  it 'migrates global legacy recipients to visible admin routes' do
    define_legacy_schema
    ids = seed_success_rows

    migrate_up!

    expect(table_exists?(:notification_template_email_recipients)).to be(false)
    expect(table_exists?(:email_recipients)).to be(false)
    expect(table_exists?(:user_notification_template_recipients)).to be(false)
    expect(table_exists?(:user_email_role_recipients)).to be(false)

    default_target = find_row(:notification_targets, user_id: ids.fetch(:direct_admin_id), identity_key: 'default')
    expect(default_target.fetch('target_value')).to be_nil
    expect(default_target.fetch('target_kind').to_i).to eq(0)

    custom_target = find_row(:notification_targets, user_id: ids.fetch(:custom_admin_id), target_value: 'legacy-ops@example.test')
    expect(custom_target.fetch('target_kind').to_i).to eq(1)
    expect(custom_target.fetch('identity_key')).to start_with('custom:')

    daily_route = route_for(
      user_id: ids.fetch(:direct_admin_id),
      event_type: 'system.daily_report',
      template_name: 'daily_report'
    )
    payments_route = route_for(
      user_id: ids.fetch(:custom_admin_id),
      event_type: 'payments.overview',
      template_name: 'payments_overview'
    )
    expect_no_matcher(daily_route, 'subject_relation')
    expect_no_matcher(payments_route, 'subject_relation')

    suspend_route = route_for(
      user_id: ids.fetch(:custom_admin_id),
      event_type: 'user.suspended',
      template_name: 'user_suspend'
    )
    expect_matcher(suspend_route, 'subject_relation', '==', 'other_user')

    expiration_route = route_for(
      user_id: ids.fetch(:custom_admin_id),
      event_type: 'lifetime.expiration_warning',
      template_name: 'expiration_warning'
    )
    expect_matcher(expiration_route, 'subject_relation', '==', 'other_user')
    expect_matcher(expiration_route, 'object', '==', 'user')
    expect_matcher(expiration_route, 'state', '==', 'active')

    vps_expiration_route = route_for(
      user_id: ids.fetch(:direct_admin_id),
      event_type: 'lifetime.expiration_warning',
      template_name: 'expiration_warning'
    )
    expect_matcher(vps_expiration_route, 'subject_relation', '==', 'other_user')
    expect_matcher(vps_expiration_route, 'object', '==', 'vps')
    expect_matcher(vps_expiration_route, 'state', '==', 'active')

    request_route = route_for(
      user_id: ids.fetch(:direct_admin_id),
      event_type: 'request.resolved',
      template_name: 'request_resolve_role_type_state'
    )
    expect_matcher(request_route, 'subject_relation', '==', 'other_user')
    expect_matcher(request_route, 'role', '==', 'user')
    expect_matcher(request_route, 'request_type', '==', 'change')
    expect_matcher(request_route, 'request_state', '==', 'approved')

    monitoring_route = route_for(
      user_id: ids.fetch(:direct_admin_id),
      event_type: 'monitoring.monitor_state_changed',
      template_name: 'alert_role_event_state'
    )
    expect_matcher(monitoring_route, 'subject_relation', '==', 'other_user')
    expect_matcher(monitoring_route, 'role', '==', 'admin')
    expect_matcher(monitoring_route, 'monitor_name', '==', 'monthly_traffic')
    expect_matcher(monitoring_route, 'state', '==', 'acknowledged')
  end

  it 'recreates legacy recipient tables on rollback without reconstructing rows' do
    define_legacy_schema
    seed_success_rows
    migrate_up!

    migrate_down!

    expect(table_exists?(:email_recipients)).to be(true)
    expect(table_exists?(:notification_template_email_recipients)).to be(true)
    expect(table_exists?(:user_email_role_recipients)).to be(true)
    expect(table_exists?(:user_notification_template_recipients)).to be(true)
    expect(index_exists?(:notification_template_email_recipients,
                         :notification_template_email_recipients_unique)).to be(true)
    expect(index_exists?(:user_email_role_recipients,
                         :index_user_email_role_recipients_on_user_id_and_role)).to be(true)
    expect(index_exists?(:user_notification_template_recipients,
                         :user_id_notification_template_id)).to be(true)
    expect(row_count(:email_recipients)).to eq(0)
    expect(row_count(:notification_template_email_recipients)).to eq(0)
  end

  it 'fails loudly for unknown template mappings' do
    define_legacy_schema
    insert_row(:users, login: 'admin', email: 'admin@example.test', level: 90)
    template_id = insert_template('unknown_template', 'Unknown template')
    recipient_id = insert_row(:email_recipients, label: 'admin', to: 'admin@example.test', cc: nil, bcc: nil)
    link_template(template_id, recipient_id)

    expect { migrate_up! }.to raise_error(/unknown templates: unknown_template/)
  end

  it 'fails loudly when a recipient cannot be resolved to one user' do
    define_legacy_schema
    template_id = insert_template('daily_report', 'Daily report')
    recipient_id = insert_row(:email_recipients, label: 'missing', to: 'missing@example.test', cc: nil, bcc: nil)
    link_template(template_id, recipient_id)

    expect { migrate_up! }.to raise_error(/cannot resolve legacy notification recipient/)
  end

  it 'fails loudly when a recipient resolves to a non-admin user' do
    define_legacy_schema
    insert_row(:users, login: 'member', email: 'member@example.test', level: 1)
    template_id = insert_template('daily_report', 'Daily report')
    recipient_id = insert_row(:email_recipients, label: 'member', to: 'member@example.test', cc: nil, bcc: nil)
    link_template(template_id, recipient_id)

    expect { migrate_up! }.to raise_error(/resolves to non-admin user member/)
  end
end
