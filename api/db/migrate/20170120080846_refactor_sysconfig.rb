class RefactorSysconfig < ActiveRecord::Migration
  class OldSysConfig < ActiveRecord::Base
    self.table_name = 'sysconfig'
    self.primary_key = 'cfg_name'
  end

  class NewSysConfig < ActiveRecord::Base
    self.table_name = 'sysconfig_new'
  end

  def up
    create_table :sysconfig_new do |t|
      t.string  :category,        null: false, limit: 75
      t.string  :name,            null: false, limit: 75
      t.string  :data_type,       null: false, default: 'Text'
      t.text    :value,           null: true
      t.string  :label,           null: true
      t.text    :description,     null: true

      # User levels:
      #   nil     inaccesible via the API
      #   0       public, no authentication required
      #   >0      user has to have equal or higher user level in order to access
      #           this setting
      t.integer :min_user_level,  null: true
      t.timestamps
    end

    add_index :sysconfig_new, :category
    add_index :sysconfig_new, [:category, :name], unique: true

    OldSysConfig.all.each do |cfg|
      cat, name, type, level = name_up(cfg.cfg_name)

      NewSysConfig.create!(
          category: cat,
          name: name,
          data_type: type || 'Text',
          value: cfg.cfg_value,
          min_user_level: level,
      )
    end

    drop_table :sysconfig
    rename_table :sysconfig_new, :sysconfig
  end

  def down
    ActiveRecord::Base.connection.execute(
        "CREATE TABLE `sysconfig_new` (
          `cfg_name` varchar(127) NOT NULL,
          `cfg_value` text,
          PRIMARY KEY (`cfg_name`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8;"
    )

    OldSysConfig.all.each do |cfg|
      name = name_down(cfg.category, cfg.name)

      NewSysConfig.create!(
          cfg_name: name,
          cfg_value: cfg.value,
      )
    end

    drop_table :sysconfig
    rename_table :sysconfig_new, :sysconfig
  end

  def name_up(name)
    case name
    when 'node_public_key', 'node_private_key', 'node_key_type'
      [:node, name[5..-1]]

    when 'snapshot_download_base_url'
      [:core, name, 'String', 1]

    when 'general_base_url'
      [:webui, 'base_url', 'String', 0]

    when 'page_title'
      [:webui, 'document_title', 'String', 0]

    when 'noticeboard', 'index_info_box_title', 'index_info_box_content'
      [:webui, name, 'Text', 0]

    when 'adminbox_content'
      [:webui, 'sidebar', 'Text', 0]

    when /mailer_requests_(admin|member)_sub/
      [:webui, name, 'String', 99]

    when /mailer_requests_(admin|member)_text/
      [:webui, name, 'Text', 99]

    when /mailer_from_/
      [:webui, name, 'String', 99]

    when 'payments_enabled'
      [:webui, name, 'Boolean', 1]

    else
      [:unset, name]
    end
  end

  def name_down(cat, name)
    return "node_#{name}" if cat == 'node'

    if cat == 'webui'
      return 'general_base_url' if name == 'base_url'
      return 'page_title' if name == 'document_title'
      return 'adminbox_content' if name == 'sidebar'
    end

    name
  end
end
