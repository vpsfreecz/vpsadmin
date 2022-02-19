class VpsAdmin::API::Resources::VpsGroupRelation < HaveAPI::Resource
  model ::VpsGroupRelation
  desc 'Manage VPS group relations'

  params(:id) do
    id :id, label: 'ID'
  end

  params(:common) do
    resource VpsAdmin::API::Resources::VpsGroup, name: :vps_group
    resource VpsAdmin::API::Resources::VpsGroup, name: :other_vps_group
    string :group_relation, choices: ::VpsGroupRelation.group_relations.keys.map(&:to_s)
  end

  params(:all) do
    use :id
    use :common
  end

  class Index < HaveAPI::Actions::Default::Index
    desc 'List VPS group relations'

    input do
      resource VpsAdmin::API::Resources::User, value_label: :login
      resource VpsAdmin::API::Resources::VpsGroup
    end

    output(:object_list) do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      input whitelist: %i(vps_group)
      restrict vps_groups: {user_id: u.id}
      allow
    end

    def query
      q = self.class.model.joins(:vps_group).where(with_restricted)

      q = q.where(vps_groups: {user_id: input[:user].id}) if input[:user]

      if input[:vps_group]
        grp_id = input[:vps_group].id
        q = q.where('vps_group_id = ? OR other_vps_group_id = ?', grp_id, grp_id)
      end

      q
    end

    def count
      query.count
    end

    def exec
      with_includes(query).limit(input[:limit]).offset(input[:offset])
    end
  end

  class Create < HaveAPI::Actions::Default::Create
    desc 'Create a new VPS group relation'

    input do
      use :common
      patch :vps_group, required: true
      patch :other_vps_group, required: true
      patch :group_relation, required: true
    end

    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      allow
    end

    def exec
      if input[:vps_group].nil? || input[:other_vps_group].nil?
        error('provide both vps_group and other_vps_group')
      end

      if current_user.role != :admin
        if input[:vps_group].user_id != current_user.id
          error('invalid VPS group', {vps_group: 'access denied'})
        elsif input[:other_vps_group].user_id != current_user.id
          error('invalid VPS group', {other_vps_group: 'access denied'})
        end
      end

      if input[:vps_group].user_id != input[:other_vps_group].user_id
        error('mismatching group owner')
      end

      ::VpsGroupRelation.create!(input)

    rescue ActiveRecord::RecordInvalid => e
      error('create failed', e.record.errors.to_hash)

    rescue ActiveRecord::RecordNotUnique
      error('group relation already exists')
    end
  end

  class Show < HaveAPI::Actions::Default::Show
    desc 'Show VPS group relation'

    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      restrict vps_groups: {user_id: u.id}
      allow
    end

    def exec
      self.class.model
        .joins(:vps_group)
        .find_by!(with_restricted(id: params[:vps_group_relation_id]))
    end
  end

  class Delete < HaveAPI::Actions::Default::Delete
    desc 'Delete VPS group relation'

    authorize do |u|
      allow if u.role == :admin
      restrict vps_groups: {user_id: u.id}
      allow
    end

    def exec
      rel = self.class.model
        .joins(:vps_group)
        .find_by!(with_restricted(id: params[:vps_group_relation_id]))

      rel.destroy!
      ok
    end
  end
end
