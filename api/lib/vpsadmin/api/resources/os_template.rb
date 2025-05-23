class VpsAdmin::API::Resources::OsTemplate < HaveAPI::Resource
  model ::OsTemplate
  desc 'Manage OS templates'

  params(:id) do
    id :id, label: 'ID', desc: 'OS template ID'
  end

  params(:common) do
    resource VpsAdmin::API::Resources::OsFamily, label: 'OS family'
    string :name, label: 'Name', desc: 'Template file name'
    string :label, label: 'Label', desc: 'Human-friendly label'
    text :info, label: 'Info', desc: 'Information about template'
    bool :enabled, label: 'Enabled', desc: 'Enable/disable template usage'
    bool :supported, label: 'Supported', desc: 'Is template known to work?'
    integer :order, label: 'Order', desc: 'Template order'
    string :hypervisor_type, choices: ::OsTemplate.hypervisor_types.keys, default: 'vpsadminos'
    string :cgroup_version, choices: ::OsTemplate.cgroup_versions.keys, default: 'cgroup_any'
    bool :manage_hostname, label: 'Manage hostname'
    bool :manage_dns_resolver, label: 'Manage DNS resolver'
    bool :enable_script, label: 'vpsAdmin user scripts'
    bool :enable_cloud_init, label: 'Cloud-init'
    string :vendor
    string :variant
    string :arch
    string :distribution
    string :version
    text :config, desc: 'Advanced configuration in YAML', db_name: :config_string
  end

  params(:all) do
    use :id
    use :common
  end

  class Index < HaveAPI::Actions::Default::Index
    desc 'List OS templates'

    input do
      resource VpsAdmin::API::Resources::Location
      use :common, include: %i[hypervisor_type cgroup_version enable_script enable_cloud_init]
    end

    output(:object_list) do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      restrict enabled: true
      output whitelist: %i[id name label info supported hypervisor_type cgroup_version
                           vendor variant arch distribution version os_family
                           enable_script enable_cloud_init]
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

      if input[:os_family]
        q = q.where(os_family: input[:os_family])
      end

      %i[enable_script enable_cloud_init].each do |v|
        q = q.where(v => input[v]) if input.has_key?(v)
      end

      q
    end

    def count
      query.count
    end

    def exec
      with_pagination(query).order(:order, :label)
    end
  end

  class Show < HaveAPI::Actions::Default::Show
    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      output whitelist: %i[id name label info supported enabled hypervisor_type cgroup_version
                           vendor variant arch distribution version os_family
                           enable_script enable_cloud_init]
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

      %i[os_family label vendor variant arch distribution version].each do |v|
        patch v, required: true
      end

      %i[manage_hostname manage_dns_resolver].each do |v|
        patch v, default: true
      end
    end

    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
    end

    def exec
      cfg = input.delete(:config)
      attrs = to_db_names(input)
      attrs[:config] = YAML.safe_load(cfg) if cfg

      ::OsTemplate.create!(attrs)
    rescue ActiveRecord::RecordInvalid => e
      error!('create failed', to_param_names(e.record.errors.to_hash))
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
      cfg = input.delete(:config)
      attrs = to_db_names(input)
      attrs[:config] = YAML.safe_load(cfg) if cfg

      ::OsTemplate.find(params[:os_template_id]).update!(attrs)
    rescue ActiveRecord::RecordInvalid => e
      error!('update failed', to_param_names(e.record.errors.to_hash))
    end
  end

  class Delete < HaveAPI::Actions::Default::Delete
    authorize do |u|
      allow if u.role == :admin
    end

    def exec
      t = ::OsTemplate.find(params[:os_template_id])

      error!('The OS template is in use') if t.in_use?
      t.destroy
      ok!
    end
  end
end
