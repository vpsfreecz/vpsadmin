class VpsAdmin::API::Resources::OsTemplate < HaveAPI::Resource
  version 1
  model ::OsTemplate
  desc 'Manage OS templates'

  params(:id) do
    id :id, label: 'ID', desc: 'OS template ID', db_name: :templ_id
  end

  params(:common) do
    string :name, label: 'Name', desc: 'Template file name',
           db_name: :templ_name
    string :label, label: 'Label', desc: 'Human-friendly label',
           db_name: :templ_label
    string :info, label: 'Info', desc: 'Information about template',
           db_name: :templ_info
    bool :enabled, label: 'Enabled', desc: 'Enable/disable template usage',
         db_name: :templ_enabled
    bool :supported, label: 'Supported', desc: 'Is template known to work?',
         db_name: :templ_supported
    integer :order, label: 'Order', desc: 'Template order', db_name: :templ_order
  end

  params(:all) do
    use :id
    use :common
  end

  class Index < HaveAPI::Actions::Default::Index
    desc 'List OS templates'

    output(:object_list) do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      restrict templ_enabled: true
      output whitelist: %i(label info supported)
      allow
    end

    example do
      request({})
      response({
         os_templates: [{
             id: 26,
             name: 'scientific-6-x86_64',
             label: 'Scientific Linux 6',
             info: 'Some important notes',
             enabled: true,
             supported: true,
             order: 1
         }]
     })
    end

    def exec
      ::OsTemplate.where(with_restricted).limit(params[:os_template][:limit]).offset(params[:os_template][:offset])
    end
  end

  class Show < HaveAPI::Actions::Default::Show
    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      restrict templ_enabled: true
      output whitelist: %i(label info supported)
      allow
    end

    def prepare
      @os_template = ::OsTemplate.find_by!(with_restricted(templ_id: params[:os_template_id]))
    end

    def exec
      @os_template
    end
  end
end
