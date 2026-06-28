module VpsAdmin::API::Resources
  class NotificationTemplate < HaveAPI::Resource
    model ::NotificationTemplate
    desc 'Manage notification templates'

    params(:common) do
      string :name, desc: 'Template identifier'
      string :label, desc: 'Human-friendly label'
      string :template_id
      string :user_visibility, choices: ::NotificationTemplate.user_visibilities.keys.map(&:to_s)
    end

    params(:all) do
      id :id
      use :common
      datetime :created_at
      datetime :updated_at
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List notification templates'

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def query
        ::NotificationTemplate.all
      end

      def count
        query.count
      end

      def exec
        with_pagination(with_includes(query))
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'View notification template'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def prepare
        @tpl = ::NotificationTemplate.find(path_params['notification_template_id'])
      end

      def exec
        @tpl
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Create a notification template'

      input do
        use :common
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        tpl = ::NotificationTemplate.new(input)

        if tpl.save
          ok!(tpl)

        else
          error!('save failed', tpl.errors.to_hash)
        end
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      desc 'Update a notification template'

      input do
        use :common
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        tpl = ::NotificationTemplate.find(path_params['notification_template_id'])

        if tpl.update(input)
          ok!(tpl)

        else
          error!('update failed', tpl.errors.to_hash)
        end
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      desc 'Delete a notification template'

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        ::NotificationTemplate.find(path_params['notification_template_id']).destroy!
        ok!
      end
    end

    class Variant < HaveAPI::Resource
      model ::NotificationTemplateVariant
      route '{notification_template_id}/variants'
      desc 'Manage notification template variants'

      params(:common) do
        string :protocol, choices: ::NotificationTemplateVariant.protocols.keys.map(&:to_s)
        resource Language
        string :from, nullable: true
        string :reply_to, nullable: true
        string :return_path, nullable: true
        string :subject, nullable: true
        text :text, nullable: true
        text :html, nullable: true
        custom :options, nullable: true
      end

      params(:all) do
        id :id
        use :common
        datetime :created_at
        datetime :updated_at
      end

      class Index < HaveAPI::Actions::Default::Index
        desc 'List notification template variants'

        output(:object_list) do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
        end

        def query
          ::NotificationTemplateVariant.where(notification_template_id: path_params['notification_template_id'])
        end

        def count
          query.count
        end

        def exec
          with_pagination(with_includes(query))
        end
      end

      class Show < HaveAPI::Actions::Default::Show
        desc 'Show a notification template variant'

        output do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
        end

        def prepare
          @tr = ::NotificationTemplateVariant.find_by!(
            id: path_params['variant_id'],
            notification_template_id: path_params['notification_template_id']
          )
        end

        def exec
          @tr
        end
      end

      class Create < HaveAPI::Actions::Default::Create
        desc 'Create a notification template variant'

        input do
          use :common
        end

        output do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
        end

        def exec
          input.update(notification_template: ::NotificationTemplate.find(path_params['notification_template_id']))
          tr = ::NotificationTemplateVariant.new(input)

          if tr.save
            ok!(tr)

          else
            error!('save failed', tr.errors.to_hash)
          end
        end
      end

      class Update < HaveAPI::Actions::Default::Update
        desc 'Update a notification template variant'

        input do
          use :common
        end

        output do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
        end

        def exec
          tr = ::NotificationTemplateVariant.find_by!(
            id: path_params['variant_id'],
            notification_template_id: path_params['notification_template_id']
          )

          if tr.update(input)
            ok!(tr)

          else
            error!('update failed', tr.errors.to_hash)
          end
        end
      end

      class Delete < HaveAPI::Actions::Default::Delete
        desc 'Delete a notification template variant'

        authorize do |u|
          allow if u.role == :admin
        end

        def exec
          ::NotificationTemplateVariant.find_by!(
            id: path_params['variant_id'],
            notification_template_id: path_params['notification_template_id']
          ).destroy!
          ok!
        end
      end
    end
  end
end
