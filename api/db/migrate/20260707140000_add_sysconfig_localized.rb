class AddSysconfigLocalized < ActiveRecord::Migration[8.1]
  LOCALIZED_SETTINGS = [
    %w[webui noticeboard],
    %w[webui index_info_box_title],
    %w[webui index_info_box_content],
    %w[webui sidebar],
    %w[plugin_payments payment_instructions]
  ].freeze

  def up
    add_column :sysconfig, :localized, :boolean, null: false, default: false

    LOCALIZED_SETTINGS.each do |category, name|
      mark_localized(category, name)
    end
  end

  def down
    remove_column :sysconfig, :localized
  end

  protected

  def mark_localized(category, name)
    connection.update(<<~SQL.squish)
      UPDATE #{connection.quote_table_name('sysconfig')}
      SET localized = #{connection.quote(true)}
      WHERE category = #{connection.quote(category)}
        AND name = #{connection.quote(name)}
    SQL
  end
end
