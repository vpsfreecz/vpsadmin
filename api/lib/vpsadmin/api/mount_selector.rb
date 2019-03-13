module VpsAdmin::API
  class MountSelector
    VpsMounts = Struct.new(:vps, :mounts) do
      def <<(mount)
        mounts << mount
      end

      def sort!
        mounts.sort! { |a, b| a.dst <=> b.dst }
      end
    end

    # @param dip [::DatasetInPool]
    def initialize(dip)
      @dip = dip
      @mounts = {}
      find_mounts
    end

    # @yieldparam vps [::Vps]
    # @yieldparam mounts [Array<::Mount>]
    def each_vps_mount
      mounts.each do |vps_id, vps_mounts|
        yield(vps_mounts.vps, vps_mounts.mounts)
      end
    end

    # @yieldparam vps [::Vps]
    # @yieldparam mounts [Array<::Mount>]
    def each_vps_unmount
      mounts.each do |vps_id, vps_mounts|
        yield(vps_mounts.vps, vps_mounts.mounts.reverse)
      end
    end

    protected
    attr_reader :dip, :mounts

    def find_mounts
      # Fetch ids of all descendant datasets in pool
      dataset_in_pools = [dip.id] + dip.dataset.subtree.joins(
        :dataset_in_pools
      ).where(
        dataset_in_pools: {pool_id: dip.pool_id}
      ).pluck('dataset_in_pools.id')

      # Find mounts of all datasets in pools
      ::Mount.includes(
        :vps, dataset_in_pool: [:dataset, pool: [:node]]
      ).where(
        enabled: true,
        master_enabled: true,
      ).where(
        'dataset_in_pool_id IN (?)', dataset_in_pools
      ).order('dst ASC').each do |m|
        mounts[m.vps_id] ||= VpsMounts.new(m.vps, [])
        mounts[m.vps_id] << m

        # Find mounts that are mounted anywhere below m.dst on m.vps
        ::Mount.includes(
        :vps, dataset_in_pool: [:dataset, pool: [:node]]
        ).where(vps: m.vps, enabled: true, master_enabled: true).where(
          'dst LIKE ?', "#{m.dst}/%"
        ).order('dst ASC').each do |m2|
          mounts[m.vps_id] << m2
        end
      end

      mounts.each_value(&:sort!)
    end
  end
end
