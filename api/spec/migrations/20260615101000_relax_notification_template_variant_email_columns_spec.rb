# frozen_string_literal: true

require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20260615101000_relax_notification_template_variant_email_columns')

RSpec.describe RelaxNotificationTemplateVariantEmailColumns do
  def define_variant_schema
    define_schema do
      create_table :notification_template_variants do |t|
        t.integer :notification_template_id, null: false
        t.integer :language_id, null: false
        t.integer :protocol, null: false, default: 0
        t.string :from, null: false
        t.string :subject, null: false
        t.text :text
        t.text :html
      end
    end
  end

  it 'allows non-email variants to omit email-only columns' do
    define_variant_schema

    migrate_up!

    expect(column(:notification_template_variants, :from).null).to be(true)
    expect(column(:notification_template_variants, :subject).null).to be(true)

    insert_row(
      :notification_template_variants,
      notification_template_id: 1,
      language_id: 1,
      protocol: 1,
      from: nil,
      subject: nil,
      text: 'SMS body',
      html: nil
    )
    expect(row_count(:notification_template_variants)).to eq(1)
  end

  it 'removes non-email variants before rolling back nullability' do
    define_variant_schema
    insert_row(
      :notification_template_variants,
      notification_template_id: 1,
      language_id: 1,
      protocol: 0,
      from: 'support@example.test',
      subject: 'Mail',
      text: 'body',
      html: nil
    )
    migrate_up!
    insert_row(
      :notification_template_variants,
      notification_template_id: 1,
      language_id: 2,
      protocol: 1,
      from: nil,
      subject: nil,
      text: 'SMS body',
      html: nil
    )

    migrate_down!

    expect(column(:notification_template_variants, :from).null).to be(false)
    expect(column(:notification_template_variants, :subject).null).to be(false)
    expect(row_count(:notification_template_variants)).to eq(1)
  end
end
