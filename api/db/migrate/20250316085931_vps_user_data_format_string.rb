class VpsUserDataFormatString < ActiveRecord::Migration[7.2]
  class VpsUserData < ActiveRecord::Base; end

  FORMATS = %w[script cloudinit_config cloudinit_script].freeze

  def up
    VpsUserData.all.each do |data|
      next if FORMATS[data.format]

      raise "VpsUserData id=#{data.id}: unsupported format #{data.format.inspect}"
    end

    remove_index :vps_user_data, :format

    add_column :vps_user_data, :format_string, :string, limit: 30, default: 'script', null: false

    VpsUserData.all.each do |data|
      data.update!(format_string: FORMATS[data.format])
    end

    remove_column :vps_user_data, :format
    rename_column :vps_user_data, :format_string, :format

    add_index :vps_user_data, :format
  end

  def down
    VpsUserData.all.each do |data|
      next if FORMATS.index(data.format)

      raise "VpsUserData id=#{data.id}: unsupported format #{data.format.inspect}"
    end

    remove_index :vps_user_data, :format

    add_column :vps_user_data, :format_int, :integer, default: 0, null: false

    VpsUserData.all.each do |data|
      data.update!(format_int: FORMATS.index(data.format))
    end

    remove_column :vps_user_data, :format
    rename_column :vps_user_data, :format_int, :format

    add_index :vps_user_data, :format
  end
end
