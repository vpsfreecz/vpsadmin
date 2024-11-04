class AddOsFamilies < ActiveRecord::Migration[7.1]
  class OsFamily < ActiveRecord::Base; end
  class OsTemplate < ActiveRecord::Base; end

  FAMILIES = {
    'almalinux' => 'AlmaLinux',
    'alpine' => 'Alpine Linux',
    'arch' => 'Arch Linux',
    'centos' => 'CentOS',
    'chimera' => 'Chimera Linux',
    'debian' => 'Debian',
    'devuan' => 'Devuan',
    'fedora' => 'Fedora',
    'gentoo' => 'Gentoo',
    'guix' => 'GNU Guix System',
    'nixos' => 'NixOS',
    'opensuse' => 'openSUSE',
    'rocky' => 'Rocky Linux',
    'slackware' => 'Slackware',
    'ubuntu' => 'Ubuntu',
    'void' => 'Void Linux',
    'other' => 'Other'
  }.freeze

  def change
    create_table :os_families do |t|
      t.string     :label,                    null: false, limit: 255
      t.text       :description,              null: false, default: ''
      t.timestamps                            null: false
    end

    add_column :os_templates, :os_family_id, :bigint, null: true
    add_index :os_templates, :os_family_id

    reversible do |dir|
      dir.up do
        families = {}

        FAMILIES.each do |name, label|
          families[name] = OsFamily.create!(label:)
        end

        OsTemplate.all.each do |tpl|
          family =
            if tpl.distribution
              families[tpl.distribution]
            else
              families[tpl.name.split('-').first]
            end

          tpl.update!(os_family_id: (family || families['other']).id)
        end
      end
    end

    change_column_null :os_templates, :os_family_id, false
  end
end
