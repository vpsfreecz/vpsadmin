require 'json'

class LocalizeWebuiSysconfig < ActiveRecord::Migration[8.1]
  SETTINGS = {
    noticeboard: 'Text',
    index_info_box_title: 'String',
    index_info_box_content: 'Text',
    sidebar: 'Text'
  }.freeze

  def up
    SETTINGS.each_key do |name|
      row = sysconfig_row('webui', name)

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
        insert_sysconfig('webui', name, 'Hash', {}, localized: true)
      end
    end
  end

  def down
    SETTINGS.each do |name, type|
      row = sysconfig_row('webui', name)
      next unless row

      value = decode_value(row.fetch('value'))
      scalar = if value.is_a?(Hash)
                 value['en'].presence || value.values.find(&:present?) || ''
               else
                 value
               end

      update_sysconfig(
        row.fetch('id'),
        data_type: type,
        value: scalar.to_s,
        localized: false
      )
    end
  end

  protected

  def sysconfig_row(category, name)
    connection.select_one(<<~SQL.squish)
      SELECT *
      FROM #{connection.quote_table_name('sysconfig')}
      WHERE category = #{connection.quote(category)}
        AND name = #{connection.quote(name.to_s)}
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

  def insert_sysconfig(category, name, data_type, value, localized:)
    now = Time.now
    attrs = {
      category:,
      name: name.to_s,
      data_type:,
      value: encode_value(value),
      min_user_level: 0,
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
