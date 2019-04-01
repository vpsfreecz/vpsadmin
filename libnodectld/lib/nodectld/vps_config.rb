module NodeCtld
  module VpsConfig
    # @param pool_fs [String]
    # @param vps_id [Integer]
    # @yiledparam cfg [VpsConfig::TopLevel]
    def self.open(pool_fs, vps_id)
      cfg = TopLevel.new(pool_fs, vps_id)

      if block_given?
        ret = yield(cfg)
        cfg.save
        ret
      else
        cfg
      end
    end
  end
end
