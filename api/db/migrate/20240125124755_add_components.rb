class AddComponents < ActiveRecord::Migration[7.1]
  class Component < ActiveRecord::Base ; end

  def change
    create_table :components do |t|
      t.string  :name,                        null: false, limit: 30
      t.string  :label,                       null: false, limit: 100
      t.text    :description,                 null: false, default: ''
    end

    add_index :components, :name, unique: true

    reversible do |dir|
      dir.up do
        Component.insert_all!([
          {
            name: 'api',
            label: 'API Server',
          },
          {
            name: 'console',
            label: 'Remote Console Server',
          },
          {
            name: 'webui',
            label: 'Web Interface',
          },
        ])
      end
    end
  end
end
