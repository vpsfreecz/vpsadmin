module VpsAdmin::API::Resources
  class NotificationTarget < HaveAPI::Resource
    desc 'Manage reusable notification targets'
    model ::NotificationTarget

    module DeliveryMethodControls
      protected

      def enable_delivery_method_for_admin!(user, delivery_method)
        delivery_method = ::UserNotificationDeliveryMethod.normalize_delivery_method(delivery_method)
        return unless current_user.role == :admin
        return unless ::UserNotificationDeliveryMethod.known_delivery_method?(delivery_method)
        return if user.notification_delivery_method_enabled?(delivery_method)

        user.set_notification_delivery_method!(delivery_method, true)
      end
    end

    params(:common) do
      resource User, value_label: :login
      string :action,
             choices: { values: ::NotificationTarget.action_labels },
             load_validators: false
      string :label, nullable: true
      string :target_kind,
             choices: { values: ::NotificationTarget.target_kind_labels },
             load_validators: false
      text :target_value, nullable: true
      bool :enabled
      bool :delivery_method_enabled
      datetime :verified_at, nullable: true
      bool :verified
      string :verification_token, nullable: true
      text :config_json, label: 'Configuration'
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
      datetime :created_at
      datetime :updated_at
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List notification targets'

      input do
        use :common, include: %i[user action enabled]
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
        %i[user action enabled].each do |v|
          q = q.where(v => input[v]) if input.has_key?(v)
        end
        q
      end

      def count
        query.count
      end

      def exec
        with_pagination(query.order(:action, :label, :id))
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show notification target'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        allow
      end

      def exec
        self.class.model.find_by!(with_restricted(id: path_params['notification_target_id']))
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      include DeliveryMethodControls

      desc 'Create notification target'

      input do
        use :common, include: %i[user action label target_kind target_value enabled]
        text :secret, nullable: true
        %i[action].each { |v| patch v, required: true }
      end

      output do
        use :all
      end

      authorize do |_u|
        allow
      end

      def exec
        owner = input[:user] || current_user
        error!('access denied') if current_user.role != :admin && owner != current_user

        target = nil
        self.class.model.transaction do
          target = owner.notification_targets.new(
            action: input[:action],
            label: input[:label],
            target_kind: input[:target_kind] || default_target_kind,
            target_value: input[:target_value],
            enabled: input.has_key?(:enabled) ? input[:enabled] : true,
            secret: input[:secret]
          )
          target.skip_delivery_method_enabled_validation = current_user.role == :admin
          target.save!
          target.generate_verification_token! if target.telegram_action?
          if current_user.role == :admin && target.admin_verification_skippable?
            target.mark_verified!
          elsif target.sms_action?
            target.generate_sms_verification_code!
          elsif target.email_verification_required?
            target.generate_email_verification_token!
          end
          enable_delivery_method_for_admin!(owner, target.action)
        end

        target
      rescue ActiveRecord::RecordInvalid => e
        error!('create failed', e.record.errors.to_hash)
      end

      def default_target_kind
        input[:action] == 'email' ? 'default_recipient' : 'custom'
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      include DeliveryMethodControls

      desc 'Update notification target'

      input do
        use :common, include: %i[label target_kind target_value enabled]
        text :secret, nullable: true
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
        target = self.class.model.find_by!(with_restricted(id: path_params['notification_target_id']))

        attrs = {}
        %i[label target_kind target_value enabled].each do |v|
          attrs[v] = input[v] if input.has_key?(v)
        end
        attrs[:secret] = input[:secret] if input.has_key?(:secret) && !input[:secret].nil?

        self.class.model.transaction do
          target.skip_delivery_method_enabled_validation = current_user.role == :admin
          target.update!(attrs)
          target.mark_verified! if current_user.role == :admin && target.admin_verification_skippable?
          enable_delivery_method_for_admin!(target.user, target.action)
        end

        target
      rescue ActiveRecord::RecordInvalid => e
        error!('update failed', e.record.errors.to_hash)
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      desc 'Delete notification target'

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        allow
      end

      def exec
        target = self.class.model.find_by!(with_restricted(id: path_params['notification_target_id']))
        target.destroy!
        ok!
      end
    end

    class SendEmailVerification < HaveAPI::Action
      desc 'Send e-mail verification link'
      route '{notification_target_id}/send_email_verification'
      http_method :post

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        allow
      end

      def exec
        target = ::NotificationTarget.find_by!(with_restricted(id: path_params['notification_target_id']))
        error!('notification target is not a custom e-mail') unless target.email_verification_required?
        error!('e-mail target is already verified') if target.verified?
        error!('e-mail delivery method is not enabled for this user') unless target.delivery_method_enabled?
        error!('e-mail verification link was sent recently') unless target.email_verification_send_available?

        target.ensure_email_verification_token!
        VpsAdmin::API::Notifications.send_email_verification!(target)
        target.reload
      rescue VpsAdmin::API::Notifications::EmailVerificationDeliveryError => e
        error!(e.message)
      rescue ActiveRecord::RecordInvalid => e
        error!('update failed', e.record.errors.to_hash)
      end
    end

    class ConfirmEmailVerification < HaveAPI::Action
      desc 'Confirm e-mail verification token'
      route '{notification_target_id}/confirm_email_verification'
      http_method :post

      input do
        string :token, required: true
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
        target = ::NotificationTarget.find_by!(with_restricted(id: path_params['notification_target_id']))
        error!('notification target is not a custom e-mail') unless target.email_verification_required?
        unless target.confirm_email_verification_token!(input[:token])
          error!('e-mail verification token is invalid or expired')
        end

        target
      rescue ActiveRecord::RecordInvalid => e
        error!('update failed', e.record.errors.to_hash)
      end
    end

    class CreatePairingToken < HaveAPI::Action
      desc 'Create Telegram pairing token'
      route '{notification_target_id}/create_pairing_token'
      http_method :post

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        allow
      end

      def exec
        target = ::NotificationTarget.find_by!(with_restricted(id: path_params['notification_target_id']))
        error!('notification target is not Telegram') unless target.telegram_action?
        error!('Telegram delivery is not configured') unless target.action_available?

        target.generate_verification_token!
        target
      rescue ActiveRecord::RecordInvalid => e
        error!('update failed', e.record.errors.to_hash)
      end
    end

    class SendSmsVerificationCode < HaveAPI::Action
      desc 'Send SMS verification code'
      route '{notification_target_id}/send_sms_verification_code'
      http_method :post

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        allow
      end

      def exec
        target = ::NotificationTarget.find_by!(with_restricted(id: path_params['notification_target_id']))
        error!('notification target is not SMS') unless target.sms_action?
        error!('SMS delivery is not configured') unless target.action_available?
        error!('SMS delivery method is not enabled for this user') unless target.delivery_method_enabled?
        error!('SMS verification code was sent recently') unless target.sms_verification_send_available?

        target.ensure_sms_verification_code!
        VpsAdmin::API::Notifications.send_sms_verification_code!(target)
        target.reload
      rescue VpsAdmin::API::Notifications::SmsGatewayResponseError => e
        target&.update(last_error: e.message)
        error!(e.message)
      rescue ActiveRecord::RecordInvalid => e
        error!('update failed', e.record.errors.to_hash)
      end
    end

    class ConfirmSmsVerificationCode < HaveAPI::Action
      desc 'Confirm SMS verification code'
      route '{notification_target_id}/confirm_sms_verification_code'
      http_method :post

      input do
        string :code, required: true
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
        target = ::NotificationTarget.find_by!(with_restricted(id: path_params['notification_target_id']))
        error!('notification target is not SMS') unless target.sms_action?
        error!('SMS verification code is invalid or expired') unless target.confirm_sms_verification_code!(input[:code])

        target
      rescue ActiveRecord::RecordInvalid => e
        error!('update failed', e.record.errors.to_hash)
      end
    end
  end
end
