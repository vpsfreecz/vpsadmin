class VpsAdmin::API::Resources::OsTemplate < HaveAPI::Resource
  model ::OsTemplate
  desc 'Manage OS templates'

  params(:id) do
    id :id, label: 'ID', desc: 'OS template ID'
  end

  params(:common) do
    string :name, label: 'Name', desc: 'Template file name'
    string :label, label: 'Label', desc: 'Human-friendly label'
    text :info, label: 'Info', desc: 'Information about template'
    bool :enabled, label: 'Enabled', desc: 'Enable/disable template usage'
    bool :supported, label: 'Supported', desc: 'Is template known to work?'
    integer :order, label: 'Order', desc: 'Template order'
    string :hypervisor_type, choices: ::OsTemplate.hypervisor_types.keys, default: 'vpsadminos'
    string :cgroup_version, choices: ::OsTemplate.cgroup_versions.keys, default: 'cgroup_any'
    string :vendor
    string :variant
    string :arch
    string :distribution
    string :version
  end

  params(:all) do
    use :id
    use :common
  end

  class Index < HaveAPI::Actions::Default::Index
    desc 'List OS templates'

    input do
      resource VpsAdmin::API::Resources::Location
      use :common, include: %i[hypervisor_type cgroup_version]
    end

    output(:object_list) do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      restrict enabled: true
      output whitelist: %i[id name label info supported hypervisor_type cgroup_version]
      allow
    end

    def query
      q = ::OsTemplate.where(with_restricted)

      if input[:location]
        hypervisor_types = ::Node.where(
          location_id: input[:location].id
        ).group('hypervisor_type').pluck('hypervisor_type')

        q = q.where(hypervisor_type: hypervisor_types)
      end

      q = if input[:hypervisor_type]
            q.where(
              hypervisor_type: ::OsTemplate.hypervisor_types[input[:hypervisor_type]]
            )
          else
            q.where(hypervisor_type: 'vpsadminos')
          end

      if input[:cgroup_version]
        q = q.where(
          cgroup_version: ::OsTemplate.cgroup_versions[input[:cgroup_version]]
        )
      end

      q
    end

    def count
      query.count
    end

    def exec
      query
        .order(:order, :label)
        .limit(input[:limit])
        .offset(input[:offset])
    end
  end

  class Show < HaveAPI::Actions::Default::Show
    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      output whitelist: %i[id name label info supported enabled hypervisor_type cgroup_version]
      allow
    end

    def prepare
      @os_template = ::OsTemplate.find_by!(with_restricted(id: params[:os_template_id]))
    end

    def exec
      @os_template
    end
  end

  class Create < HaveAPI::Actions::Default::Create
    input do
      use :common, exclude: %i[name]
      %i[label vendor variant arch distribution version].each do |v|
        patch v, required: true
      end
    end

    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
    end

    def exec
      ::OsTemplate.create!(to_db_names(input))
    rescue ActiveRecord::RecordInvalid => e
      error('create failed', to_param_names(e.record.errors.to_hash))
    end
  end

  class Update < HaveAPI::Actions::Default::Update
    input do
      use :common, exclude: %i[name]
    end

    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
    end

    def exec
      ::OsTemplate.find(params[:os_template_id]).update!(to_db_names(input))
    rescue ActiveRecord::RecordInvalid => e
      error('update failed', to_param_names(e.record.errors.to_hash))
    end
  end

  class Delete < HaveAPI::Actions::Default::Delete
    authorize do |u|
      allow if u.role == :admin
    end

    def exec
      t = ::OsTemplate.find(params[:os_template_id])

      error('The OS template is in use') if t.in_use?
      t.destroy
      ok
    end
  end
end
