module VpsAdmin::API::Resources
  class MailTemplate < HaveAPI::Resource
    model ::MailTemplate
    desc 'Manage mail templates'

    params(:common) do
      string :name, desc: 'Template identifier'
      string :label, desc: 'Human-friendly label'
      string :template_id
      string :user_visibility, choices: ::MailTemplate.user_visibilities.keys.map(&:to_s)
    end

    params(:all) do
      id :id
      use :common
      datetime :created_at
      datetime :updated_at
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List mail templates'

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def query
        ::MailTemplate.all
      end

      def count
        query.count
      end

      def exec
        with_includes(query).offset(input[:offset]).limit(input[:limit])
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'View mail template'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def prepare
        @tpl = ::MailTemplate.find(params[:mail_template_id])
      end

      def exec
        @tpl
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Create a mail template'

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
        tpl = ::MailTemplate.new(input)

        if tpl.save
          ok(tpl)

        else
          error('save failed', tpl.errors.to_hash)
        end
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      desc 'Update a mail template'

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
        tpl = ::MailTemplate.find(params[:mail_template_id])

        if tpl.update(input)
          ok(tpl)

        else
          error('update failed', tpl.errors.to_hash)
        end
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      desc 'Delete a mail template'

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        ::MailTemplate.find(params[:mail_template_id]).destroy
        ok
      end
    end

    class Recipient < HaveAPI::Resource
      model ::MailTemplateRecipient
      route ':mail_template_id/recipients'
      desc 'Manage mail recipients'

      params(:common) do
        resource VpsAdmin::API::Resources::MailRecipient
      end

      params(:all) do
        id :id
        use :common
      end

      class Index < HaveAPI::Actions::Default::Index
        desc 'List mail recipients'

        output(:object_list) do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
        end

        def query
          ::MailTemplateRecipient.where(mail_template_id: params[:mail_template_id])
        end

        def count
          query.count
        end

        def exec
          with_includes(query).offset(input[:offset]).limit(input[:limit])
        end
      end

      class Show < HaveAPI::Actions::Default::Show
        desc 'View mail recipient'

        output do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
        end

        def prepare
          @r = ::MailTemplateRecipient.find_by!(
              mail_template_id: params[:mail_template_id],
              mail_recipient_id: params[:recipient_id]
          )
        end

        def exec
          @r
        end
      end

      class Create < HaveAPI::Actions::Default::Create
        desc 'Create a mail recipient'

        input do
          use :common
          patch :mail_recipient, required: true
        end

        output do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
        end

        def exec
          tpl = ::MailTemplate.find(params[:mail_template_id])

          r = ::MailTemplateRecipient.new(
              mail_template: tpl,
              mail_recipient: input[:mail_recipient]
          )

          if r.save
            ok(r)

          else
            error('save failed', r.errors.to_hash)
          end
        end
      end

      class Delete < HaveAPI::Actions::Default::Delete
        desc 'Delete a mail recipient'

        authorize do |u|
          allow if u.role == :admin
        end

        def exec
          ::MailTemplateRecipient.find_by!(
              mail_template_id: params[:mail_template_id],
              mail_recipient_id: params[:recipient_id]
          ).destroy
          ok
        end
      end
    end

    class Translation < HaveAPI::Resource
      model ::MailTemplateTranslation
      route ':mail_template_id/translations'
      desc 'Manage mail templates'

      params(:common) do
        resource Language
        string :from
        string :reply_to
        string :return_path
        string :subject
        text :text_plain
        text :text_html
      end

      params(:all) do
        id :id
        use :common
        datetime :created_at
        datetime :updated_at
      end

      class Index < HaveAPI::Actions::Default::Index
        desc 'List mail template translations'

        output(:object_list) do
          use :all
        end
        
        authorize do |u|
          allow if u.role == :admin
        end

        def query
          ::MailTemplateTranslation.where(mail_template_id: params[:mail_template_id])
        end

        def count
          query.count
        end

        def exec
          with_includes(query).offset(input[:offset]).limit(input[:limit])
        end
      end

      class Show < HaveAPI::Actions::Default::Show
        desc 'Show a mail template translation'

        output do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
        end

        def prepare
          @tr = ::MailTemplateTranslation.find_by!(
              id: params[:translation_id],
              mail_template_id: params[:mail_template_id],
          )
        end

        def exec
          @tr
        end
      end
    
      class Create < HaveAPI::Actions::Default::Create
        desc 'Create a mail template translation'

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
          input.update(mail_template: ::MailTemplate.find(params[:mail_template_id]))
          tr = ::MailTemplateTranslation.new(input)

          if tr.save
            ok(tr)

          else
            error('save failed', tr.errors.to_hash)
          end
        end
      end

      class Update < HaveAPI::Actions::Default::Update
        desc 'Update a mail template translation'

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
          tr = ::MailTemplateTranslation.find_by!(
              id: params[:translation_id],
              mail_template_id: params[:mail_template_id],
          )

          if tr.update(input)
            ok(tr)

          else
            error('update failed', tr.errors.to_hash)
          end
        end
      end

      class Delete < HaveAPI::Actions::Default::Delete
        desc 'Delete a mail template translation'

        authorize do |u|
          allow if u.role == :admin
        end

        def exec
          ::MailTemplateTranslation.find_by!(
              id: params[:translation_id],
              mail_template_id: params[:mail_template_id],
          ).destroy!
          ok
        end
      end
    end
  end
end
