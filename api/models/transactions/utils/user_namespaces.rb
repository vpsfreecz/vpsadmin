module Transactions::Utils
  module UserNamespaces
    def build_map(userns_map, kind)
      userns_map.user_namespace_map_entries.where(
        kind: ::UserNamespaceMapEntry.kinds[kind],
      ).order('id').map(&:to_os)
    end
  end
end
