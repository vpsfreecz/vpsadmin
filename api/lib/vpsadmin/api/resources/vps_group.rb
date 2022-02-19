class VpsAdmin::API::Resources::VpsGroup < HaveAPI::Resource
  model ::VpsGroup
  desc 'Manage VPS groups'

  params(:id) do
    id :id, label: 'ID'
  end

  params(:common) do
    resource VpsAdmin::API::Resources::User, value_label: :login
    string :label, label: 'Label'
    string :group_type, label: 'Type', choices: ::VpsGroup.group_types.keys.map(&:to_s)
    bool :status, label: 'Status'
  end

  params(:all) do
    use :id
    use :common
  end

  class Index < HaveAPI::Actions::Default::Index
    desc 'List VPS groups'

    input do
      use :common, include: %i(user)
    end

    output(:object_list) do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      input blacklist: %i(user)
      output blacklist: %i(user)
      restrict user_id: u.id
      allow
    end

    def query
      q = self.class.model.where(with_restricted)
      q = q.where(user: input[:user]) if input[:user]
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
    desc 'Create a new VPS group'

    input do
      use :common, include: %i(user label group_type)
      patch :label, required: true
      patch :group_type, required: true
    end

    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      input blacklist: %i(user)
      allow
    end

    def exec
      if current_user.role == :admin
        input[:user] ||= current_user
      else
        input[:user] = current_user
      end

      ::VpsGroup.create!(input)

    rescue ActiveRecord::RecordInvalid => e
      error('create failed', e.record.errors.to_hash)
    end
  end

  class Show < HaveAPI::Actions::Default::Show
    desc 'Show VPS group'

    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      output blacklist: %i(user)
      restrict user_id: u.id
      allow
    end

    def exec
      self.class.model.find_by!(with_restricted(id: params[:vps_group_id]))
    end
  end

  class Update < HaveAPI::Actions::Default::Update
    desc 'Update VPS group'

    input do
      use :common, include: %i(label group_type)
    end

    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      restrict user_id: u.id
      allow
    end

    def exec
      grp = self.class.model.find_by!(with_restricted(id: params[:vps_group_id]))
      grp.update!(input)
      grp

    rescue ActiveRecord::RecordInvalid => e
      error('update failed', e.record.errors.to_hash)
    end
  end

  class Delete < HaveAPI::Actions::Default::Delete
    desc 'Delete VPS group'

    authorize do |u|
      allow if u.role == :admin
      restrict user_id: u.id
      allow
    end

    def exec
      grp = self.class.model.find_by!(with_restricted(id: params[:vps_group_id]))
      grp.destroy!
      ok
    end
  end
end
