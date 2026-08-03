module VpsAdmin::API::Resources
  class NotificationReceiver < HaveAPI::Resource
    desc 'Manage notification receivers'
    model ::NotificationReceiver
    resource_events topic: :notifications, audience: :account, owner: :user

    params(:common) do
      resource User, value_label: :login
      string :label
      text :description, nullable: true
      bool :enabled
      bool :mute
      string :display_action_summary
    end

    params(:all) do
      id :id
      use :common
      datetime :created_at
      datetime :updated_at
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List notification receivers'

      input do
        use :common, include: %i[user enabled mute]
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        allow
      end

      def query
        q = self.class.model.where(with_restricted)

        %i[user enabled mute].each do |v|
          q = q.where(v => input[v]) if input.has_key?(v)
        end

        q
      end

      def count
        query.count
      end

      def exec
        with_pagination(query.order(:label, :id))
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show notification receiver'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        allow
      end

      def exec
        self.class.model.find_by!(with_restricted(id: path_params['notification_receiver_id']))
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Create notification receiver'

      input do
        use :common, include: %i[user label description enabled mute]
      end

      output do
        use :all
      end

      authorize do |_u|
        allow
      end

      def exec
        owner = input[:user] || current_user

        if current_user.role != :admin && owner != current_user
          error!('access denied')
        end

        receiver = nil
        self.class.model.transaction do
          receiver = self.class.model.create!(
            user: owner,
            label: input[:label],
            description: input[:description],
            enabled: input.has_key?(:enabled) ? input[:enabled] : true,
            mute: input.has_key?(:mute) ? input[:mute] : false
          )
          VpsAdmin::API::Events::ResourceOperations.created!(
            receiver,
            owner:,
            changed_fields: input.keys
          )
        end
        receiver
      rescue ActiveRecord::RecordInvalid => e
        error!('create failed', e.record.errors.to_hash)
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      desc 'Update notification receiver'

      input do
        use :common, include: %i[label description enabled mute]
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
        receiver = self.class.model.find_by!(with_restricted(id: path_params['notification_receiver_id']))
        self.class.model.transaction do
          receiver.update!(input)
          VpsAdmin::API::Events::ResourceOperations.updated!(
            receiver,
            owner: receiver.user,
            changed_fields: input.keys
          )
        end
        receiver
      rescue ActiveRecord::RecordInvalid => e
        error!('update failed', e.record.errors.to_hash)
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      desc 'Delete notification receiver'

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        allow
      end

      def exec
        receiver = self.class.model.find_by!(with_restricted(id: path_params['notification_receiver_id']))
        self.class.model.transaction do
          receiver.destroy!
          VpsAdmin::API::Events::ResourceOperations.deleted!(
            receiver,
            owner: receiver.user
          )
        end
        ok!
      end
    end

    class Target < HaveAPI::Resource
      model ::NotificationReceiverTarget
      resource_events topic: :notifications,
                      audience: :account,
                      owner: %i[notification_receiver user]
      route '{notification_receiver_id}/target'
      desc 'Manage notification receiver target links'

      params(:common) do
        # Receiver-target lists are normalized and use this key to join the
        # reusable target returned by NotificationTarget. The create input
        # below is a Resource value and performs target authorization.
        integer :notification_target_id,
                desc: 'ID of the reusable notification target linked to this receiver'
        string :action,
               choices: { values: ::NotificationTarget.action_labels },
               load_validators: false
        string :label, nullable: true
        string :target_kind,
               choices: { values: ::NotificationTarget.target_kind_labels },
               load_validators: false
        text :target_value, nullable: true
        bool :target_enabled
        bool :delivery_method_enabled
        datetime :verified_at, nullable: true
        bool :verified
        bool :secret_present
        text :last_error, nullable: true
        string :display_target
        string :telegram_bot_name, nullable: true
        string :telegram_bot_url, nullable: true
        string :telegram_pairing_url, nullable: true
        string :telegram_pairing_command, nullable: true
      end

      params(:all) do
        id :id
        use :common
        integer :position
        datetime :created_at
        datetime :updated_at
      end

      class Index < HaveAPI::Actions::Default::Index
        desc 'List notification receiver target links'

        output(:object_list) do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
          restrict notification_receivers: { user_id: u.id }
          allow
        end

        def query
          self.class.model
              .joins(:notification_receiver)
              .includes(:notification_target)
              .where(with_restricted(notification_receiver_id: path_params['notification_receiver_id']))
        end

        def count
          query.count
        end

        def exec
          with_pagination(query.order(:position, :id))
        end
      end

      class Show < HaveAPI::Actions::Default::Show
        desc 'Show notification receiver target link'

        output do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
          restrict notification_receivers: { user_id: u.id }
          allow
        end

        def exec
          self.class.model.joins(:notification_receiver).find_by!(
            with_restricted(
              notification_receiver_id: path_params['notification_receiver_id'],
              id: path_params['target_id']
            )
          )
        end
      end

      class Create < HaveAPI::Actions::Default::Create
        desc 'Link notification target to receiver'

        input do
          resource VpsAdmin::API::Resources::NotificationTarget,
                   name: :notification_target_id,
                   db_name: :notification_target,
                   value_label: :display_target,
                   required: true
          integer :position, nullable: true
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
          receiver = ::NotificationReceiver.find_by!(
            with_restricted(id: path_params['notification_receiver_id'])
          )
          target = ::NotificationTarget.find_by!(
            user_id: receiver.user_id,
            id: input[:notification_target_id].id
          )

          link = nil
          self.class.model.transaction do
            link = receiver.notification_receiver_targets.create!(
              notification_target: target,
              position: input[:position] || ::NotificationReceiver.next_receiver_target_position(receiver)
            )
            VpsAdmin::API::Events::ResourceOperations.created!(
              link,
              owner: receiver.user,
              changed_fields: input.keys
            )
          end
          link
        rescue ActiveRecord::RecordInvalid => e
          error!('create failed', e.record.errors.to_hash)
        end
      end

      class Update < HaveAPI::Actions::Default::Update
        desc 'Update notification receiver target link'

        input do
          integer :position, nullable: true
        end

        output do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
          restrict notification_receivers: { user_id: u.id }
          allow
        end

        def exec
          link = self.class.model.joins(:notification_receiver).find_by!(
            with_restricted(
              notification_receiver_id: path_params['notification_receiver_id'],
              id: path_params['target_id']
            )
          )

          attrs = {}
          attrs[:position] = input[:position] if input.has_key?(:position)
          self.class.model.transaction do
            link.update!(attrs)
            VpsAdmin::API::Events::ResourceOperations.updated!(
              link,
              owner: link.notification_receiver.user,
              changed_fields: attrs.keys
            )
          end
          link
        rescue ActiveRecord::RecordInvalid => e
          error!('update failed', e.record.errors.to_hash)
        end
      end

      class Delete < HaveAPI::Actions::Default::Delete
        desc 'Unlink notification target from receiver'

        authorize do |u|
          allow if u.role == :admin
          restrict notification_receivers: { user_id: u.id }
          allow
        end

        def exec
          link = self.class.model.joins(:notification_receiver).find_by!(
            with_restricted(
              notification_receiver_id: path_params['notification_receiver_id'],
              id: path_params['target_id']
            )
          )
          owner = link.notification_receiver.user
          self.class.model.transaction do
            link.destroy!
            VpsAdmin::API::Events::ResourceOperations.deleted!(link, owner:)
          end
          ok!
        end
      end
    end
  end
end
