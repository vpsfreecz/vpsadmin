require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::Dataset::FindByName < Operations::Base
    # @param user [::User]
    # @param name [String]
    # @return [::Dataset, nil]
    def run(user, name)
      # Try a direct lookup
      ds = ::Dataset.find_by(user: user, full_name: name)
      return ds if ds

      # Find by label
      parts = name.split('/')
      fail 'invalid dataset path' if parts.empty?

      top_dip =
        ::DatasetInPool
        .includes(:dataset)
        .joins(:dataset)
        .find_by!(
          label: parts.first,
          datasets: {user_id: user.id}
        )

      ::Dataset.find_by!(
        user: user,
        full_name: File.join(top_dip.dataset.full_name, *parts[1..-1]),
      )
    end
  end
end
