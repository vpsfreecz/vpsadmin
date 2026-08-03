module VpsAdmin::API::Resources
  class Mailbox < HaveAPI::Resource
    model ::Mailbox
    resource_events topic: :mail, audience: :admin
    desc 'Manage mailboxes'

    params(:id) do
      integer :id, label: 'ID'
    end

    params(:common) do
      string :label
      string :server
      integer :port
      string :user
      string :password
      bool :enable_ssl, default: true, fill: true
    end

    params(:all) do
      use :id
      use :common, exclude: %i[password]
      datetime :created_at
      datetime :updated_at
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List mailboxes'

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def query
        ::Mailbox.all
      end

      def count
        query.count
      end

      def exec
        with_pagination(query)
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show mailbox'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def prepare
        @mailbox = ::Mailbox.find(path_params['mailbox_id'])
      end

      def exec
        @mailbox
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Create a mailbox'

      input do
        use :common
        patch :label, required: true
        patch :server, required: true
        patch :user, required: true
        patch :password, required: true
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        mailbox = nil
        self.class.model.transaction do
          mailbox = ::Mailbox.create!(input)
          VpsAdmin::API::Events::ResourceOperations.created!(
            mailbox,
            changed_fields: input.keys
          )
        end
        mailbox
      rescue ActiveRecord::RecordInvalid => e
        error!('create failed', e.record.errors.to_hash)
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      desc 'Update mailbox'

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
        m = ::Mailbox.find(path_params['mailbox_id'])
        self.class.model.transaction do
          m.update!(input)
          VpsAdmin::API::Events::ResourceOperations.updated!(
            m,
            changed_fields: input.keys
          )
        end
        m
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      desc 'Delete mailbox'

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        mailbox = ::Mailbox.find(path_params['mailbox_id'])
        self.class.model.transaction do
          mailbox.destroy!
          VpsAdmin::API::Events::ResourceOperations.deleted!(mailbox)
        end
        ok!
      end
    end

    class Handler < HaveAPI::Resource
      route '{mailbox_id}/handler'
      model ::MailboxHandler
      resource_events topic: :mail, audience: :admin
      desc 'Manage mailbox handlers'

      params(:common) do
        string :class_name
        integer :order
        bool :continue
      end

      params(:all) do
        id :id
        use :common
        datetime :created_at
        datetime :updated_at
      end

      class Index < HaveAPI::Actions::Default::Index
        desc 'List mailbox handlers'

        output(:object_list) do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
        end

        def query
          ::MailboxHandler.joins(:mailbox).where(
            mailboxes: { id: path_params['mailbox_id'] }
          )
        end

        def count
          query.count
        end

        def exec
          with_pagination(query.order(:order))
        end
      end

      class Show < HaveAPI::Actions::Default::Show
        desc 'Show mailbox handler'
        resolve ->(handler) { [handler.mailbox_id, handler.id] }

        output do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
        end

        def prepare
          @handler = ::MailboxHandler.joins(:mailbox).find_by!(
            mailboxes: { id: path_params['mailbox_id'] },
            id: path_params['handler_id']
          )
        end

        def exec
          @handler
        end
      end

      class Create < HaveAPI::Actions::Default::Create
        desc 'Add mailbox handler'

        input do
          use :common
          patch :class_name, required: true
        end

        output do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
        end

        def exec
          handler = nil
          self.class.model.transaction do
            handler = ::MailboxHandler.create!(input.merge(
                                                 mailbox: ::Mailbox.find(path_params['mailbox_id'])
                                               ))
            VpsAdmin::API::Events::ResourceOperations.created!(
              handler,
              changed_fields: input.keys
            )
          end
          handler
        end
      end

      class Update < HaveAPI::Actions::Default::Update
        desc 'Update mailbox handler'

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
          h = ::MailboxHandler.joins(:mailbox).find_by!(
            mailboxes: { id: path_params['mailbox_id'] },
            id: path_params['handler_id']
          )
          self.class.model.transaction do
            h.update!(input)
            VpsAdmin::API::Events::ResourceOperations.updated!(
              h,
              changed_fields: input.keys
            )
          end
          h
        end
      end

      class Delete < HaveAPI::Actions::Default::Delete
        desc 'Delete mailbox handler'

        authorize do |u|
          allow if u.role == :admin
        end

        def exec
          handler = ::MailboxHandler.joins(:mailbox).find_by!(
            mailboxes: { id: path_params['mailbox_id'] },
            id: path_params['handler_id']
          )
          self.class.model.transaction do
            handler.destroy!
            VpsAdmin::API::Events::ResourceOperations.deleted!(handler)
          end
          ok!
        end
      end
    end
  end
end
