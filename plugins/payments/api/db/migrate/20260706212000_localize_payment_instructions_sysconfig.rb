require 'json'

class LocalizePaymentInstructionsSysconfig < ActiveRecord::Migration[8.1]
  CATEGORY = 'plugin_payments'.freeze
  NAME = 'payment_instructions'.freeze

  def up
    row = sysconfig_row

    if row
      value = decode_value(row.fetch('value'))
      localized_value = value.is_a?(Hash) ? value : { 'en' => value.to_s }
      update_sysconfig(
        row.fetch('id'),
        data_type: 'Hash',
        value: localized_value,
        localized: true
      )
    else
      insert_sysconfig('Hash', {}, localized: true)
    end
  end

  def down
    row = sysconfig_row
    return unless row

    value = decode_value(row.fetch('value'))
    scalar = if value.is_a?(Hash)
               value['en'].presence || value.values.find(&:present?) || ''
             else
               value
             end

    update_sysconfig(
      row.fetch('id'),
      data_type: 'Text',
      value: scalar.to_s,
      localized: false
    )
  end

  protected

  def sysconfig_row
    connection.select_one(<<~SQL.squish)
      SELECT *
      FROM #{connection.quote_table_name('sysconfig')}
      WHERE category = #{connection.quote(CATEGORY)}
        AND name = #{connection.quote(NAME)}
      LIMIT 1
    SQL
  end

  def update_sysconfig(id, data_type:, value:, localized:)
    updates = [
      "data_type = #{connection.quote(data_type)}",
      "value = #{connection.quote(encode_value(value))}",
      "updated_at = #{connection.quote(Time.now)}"
    ]
    updates << "localized = #{connection.quote(localized)}" if localized_column?

    connection.update(<<~SQL.squish)
      UPDATE #{connection.quote_table_name('sysconfig')}
      SET #{updates.join(', ')}
      WHERE id = #{connection.quote(id)}
    SQL
  end

  def insert_sysconfig(data_type, value, localized:)
    now = Time.now
    attrs = {
      category: CATEGORY,
      name: NAME,
      data_type:,
      value: encode_value(value),
      label: 'Payment instructions',
      min_user_level: 99,
      created_at: now,
      updated_at: now
    }
    attrs[:localized] = localized if localized_column?

    columns = attrs.keys.map { |v| connection.quote_column_name(v) }.join(', ')
    values = attrs.values.map { |v| connection.quote(v) }.join(', ')

    connection.insert(<<~SQL.squish)
      INSERT INTO #{connection.quote_table_name('sysconfig')}
        (#{columns})
      VALUES (#{values})
    SQL
  end

  def localized_column?
    connection.column_exists?(:sysconfig, :localized)
  end

  def decode_value(value)
    return nil if value.nil?

    JSON.parse(value)
  rescue JSON::ParserError
    value
  end

  def encode_value(value)
    JSON.dump(value)
  end
end
