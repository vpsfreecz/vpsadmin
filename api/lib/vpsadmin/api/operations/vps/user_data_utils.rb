module VpsAdmin::API
  module Operations::Vps::UserDataUtils
    # @param vps [::Vps]
    # @param opts [Hash]
    # @option opts [::VpsUserData] :vps_user_data
    # @option opts [String] :user_data_format
    # @option opts [String] :user_data_content
    # @param os_template [::OsTemplate]
    def set_user_data(vps, opts, os_template: nil)
      os_template ||= vps.os_template

      if opts[:vps_user_data] && (opts[:user_data_format] || opts[:user_data_content])
        raise Exceptions::OperationError, 'set either user_data or user_data_format with user_data_content'
      end

      if opts[:user_data_format] || opts[:user_data_content]
        opts[:vps_user_data] = ::VpsUserData.new(
          user: vps.user,
          label: "temporary user data for user=#{vps.user_id}",
          format: opts[:user_data_format],
          content: opts[:user_data_content]
        )

        unless opts[:vps_user_data].valid?
          raise ActiveRecord::RecordInvalid, opts[:vps_user_data]
        end

        %i[user_data_format user_data_content].each do |v|
          opts.delete(v)
        end
      end

      if opts[:vps_user_data]
        if opts[:vps_user_data].user_id != vps.user_id
          raise Exceptions::OperationError, 'Access denied to VPS user data'
        elsif !os_template.support_user_data?(opts[:vps_user_data])
          raise Exceptions::OperationError,
                "OS template #{os_template.label} does not support #{opts[:vps_user_data].format} user data"
        end
      end

      opts
    end
  end
end
