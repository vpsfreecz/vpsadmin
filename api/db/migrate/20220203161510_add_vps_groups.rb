class AddVpsGroups < ActiveRecord::Migration[6.1]
  class User < ActiveRecord::Base ; end
  class Vps < ActiveRecord::Base ; end
  class VpsGroup < ActiveRecord::Base ; end

  def change
    create_table :vps_groups do |t|
      t.belongs_to  :user,             null: false
      t.string      :label,            null: false, limit: 255
      t.integer     :group_type,       null: false, default: 0
      t.boolean     :status,           null: false, default: true
      t.timestamps
    end

    add_index :vps_groups, :status

    create_table :vps_group_relations do |t|
      t.belongs_to  :vps_group,        null: false
      t.belongs_to  :other_vps_group,  null: false
      t.integer     :group_relation,   null: false
      t.timestamps
    end

    add_index :vps_group_relations, %i(vps_group_id other_vps_group_id),
      unique: true, name: 'vps_group_relation_unique'
    add_index :vps_group_relations, :group_relation

    add_column :vpses, :vps_group_id, :integer, null: true
    add_index :vpses, :vps_group_id

    reversible do |dir|
      dir.up do
        User.where(object_state: [0,1,2]).each do |user|
          grp = VpsGroup.create!(
            user_id: user.id,
            label: 'Default group',
            group_type: 0,
          )

          Vps.where(
            user_id: user.id,
            object_state: [0,1,2],
          ).update_all(vps_group_id: grp.id)
        end
      end
    end

    # VPS groups
    # - none/no rules
    # - keep_together (all vps on the same node)
    # - keep_apart (vps must be on different nodes)
    #
    # Relations with other groups
    # - needs (groups must be on the same node, this makes sense only for keep_together)
    # - conflicts (groups must NOT be on the same node)
    #
    # VPS create
    # - choose a group for the VPS
    # - find node based on group settings and relations
    #
    # VPS migrate
    # - verify that the target node satisfies groups settings and relations
    #
    # VPS clone
    # - choose a group for the VPS
    # - find node based on group settings and relations
    #
    # there has to be checks when changing group type:
    # - for keep_together:
    #   - all vps must be on the same node
    # - for keep_apart:
    #   - all vps must be on different nodes
    #   - there's no `needs` group relation, as we couldn't satisfy that one
    #
    # groups with type keep_apart can have only conflict relations
    #
    # group operations:
    #   start/stop/restart
    #   set password
    #   deploy public key
    #   migrate (tbd, only for keep_together)
    #   clone (tbd, only for keep_together)
    #
    # admins must always have the option to break the relations
  end
end
