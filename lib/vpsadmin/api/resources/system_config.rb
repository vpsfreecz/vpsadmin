module VpsAdmin::API::Resources
  class SystemConfig < HaveAPI::Resource
    desc 'Query and set system configuration'
    model ::SysConfig

    params(:all) do
      string :category
      string :name
      string :type, db_name: :data_type
      custom :value
      string :label
      string :description
      integer :min_user_level
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List configuration variables'
      auth false

      input do
        use :all, include: %i(category)
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
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
      route ':category/:name'
      auth false

      output do
        use :all
      end

      authorize do |u|
        allow
      end

      def prepare
        q = ::SysConfig.where.not(min_user_level: nil).where(
            category: params[:category],
            name: params[:name],
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
      desc 'Update configuration variable'
      route ':category/:name'
      http_method :put

      input do
        use :all, include: %i(value)
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        cfg = ::SysConfig.find_by!(
            category: params[:category],
            name: params[:name],
        )
        cfg.update!(input)
        cfg
      end
    end
  end
end
