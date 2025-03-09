module VpsAdmin::API
  module Operations::Vps::UserDataUtils
    # @param vps [::Vps]
    # @param opts [Hash]
    # @option opts [::VpsUserData] :user_data
    # @option opts [String] :user_data_format
    # @option opts [String] :user_data_content
    def set_user_data(vps, opts)
      if opts[:user_data] && (opts[:user_data_format] || opts[:user_data_content])
        raise Exceptions::OperationError, 'set either user_data or user_data_format with user_data_content'
      end

      if opts[:user_data_format] || opts[:user_data_content]
        opts[:user_data] = ::VpsUserData.new(
          user: vps.user,
          label: "temporary user data for user=#{vps.user_id}",
          format: opts[:user_data_format],
          content: opts[:user_data_content]
        )

        unless opts[:user_data].valid?
          raise ActiveRecord::RecordInvalid, opts[:user_data]
        end

        %i[user_data_format user_data_content].each do |v|
          opts.delete(v)
        end
      end

      if opts[:user_data]
        if opts[:user_data].user_id != vps.user_id
          raise Exceptions::OperationError, 'Access denied to VPS user data'
        elsif !vps.os_template.support_user_data?(opts[:user_data])
          raise Exceptions::OperationError,
                "OS template #{vps.os_template.label} does not support #{opts[:user_data].format} user data"
        end
      end

      opts
    end
  end
end
