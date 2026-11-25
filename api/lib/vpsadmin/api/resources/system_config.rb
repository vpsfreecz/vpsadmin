module VpsAdmin::API::Resources
  class SystemConfig < HaveAPI::Resource
    desc 'Query and set system configuration'
    model ::SysConfig

    params(:all) do
      string :category
      string :name
      string :type, db_name: :data_type
      bool :localized
      custom :value, db_name: :get_value, nullable: true
      custom :choices, nullable: true, label: 'Choices',
                       desc: 'A list of value/label entries in declaration order. ' \
                             'Labels use the request language. A null value means no choices are declared.'
      bool :value_nullable, nullable: true, label: 'Value can be unset',
                            desc: 'True if a null value is allowed, false otherwise. ' \
                                  'This field is null when no choices are declared.'
      custom :localized_value, label: 'Localized value'
      string :label
      string :description
      integer :min_user_level
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List configuration variables'
      auth false

      input do
        use :all, include: %i[category]
      end

      output(:object_list) do
        use :all
      end

      authorize do |_u|
        allow
      end

      def exec
        q = ::SysConfig.where.not(min_user_level: nil)

        if current_user.nil?
          q = q.where(min_user_level: 0)

        elsif current_user.role != :admin
          q = q.where('min_user_level <= ?', current_user.level)
        end

        q = q.where(category: input[:category]) if input[:category]
        q.order('category, name')
      end
    end

    class Show < HaveAPI::Action
      desc 'Show configuration variable'
      route '{category}/{name}'
      auth false

      output do
        use :all
      end

      authorize do |_u|
        allow
      end

      def prepare
        q = ::SysConfig.where.not(min_user_level: nil).where(
          category: path_params['category'],
          name: path_params['name']
        )

        if current_user.nil?
          q = q.where(min_user_level: 0)

        elsif current_user.role != :admin
          q = q.where('min_user_level <= ?', current_user.level)
        end

        @cfg = q.take!
      end

      def exec
        @cfg
      end
    end

    class Update < HaveAPI::Action
      CleanedValue = Struct.new(:exact, :normalized)
      private_constant :CleanedValue

      desc 'Update configuration variable'
      route '{category}/{name}'
      http_method :put

      input do
        use :all, include: %i[value]
        # Choice values need exact scalar identity, including empty strings.
        # Retain the original cleaner's normalized value for ordinary settings,
        # including its normal field-scoped encoding errors.
        original_value = params.find { |parameter| parameter.name == :value }.dup
        patch :value, clean: ->(value) { CleanedValue.new(value, original_value.clean(value)) }
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        cfg = ::SysConfig.find_by!(
          category: path_params['category'],
          name: path_params['name']
        )
        value = input[:value]

        if value.is_a?(CleanedValue)
          value = cfg.choice_contract ? value.exact : value.normalized
        end

        unless cfg.choice_value_valid?(value)
          cfg.errors.add(:value, :inclusion)
          error!('Invalid configuration', cfg.errors.to_hash)
        end
        cfg.set_value(value)
        cfg.save!
        cfg
      rescue ActiveRecord::RecordInvalid => e
        error!('Invalid configuration', e.record.errors.to_hash)
      end
    end
  end
end
