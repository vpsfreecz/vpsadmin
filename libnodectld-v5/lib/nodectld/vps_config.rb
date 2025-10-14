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

    # @param pool_fs [String]
    # @param vps_id [Integer]
    # @yiledparam cfg [VpsConfig::TopLevel]
    def self.edit(pool_fs, vps_id)
      ret = nil
      cfg = TopLevel.new(pool_fs, vps_id, load: false)
      cfg.lock do
        cfg.load if cfg.exist?
        ret = yield(cfg)
        cfg.save
      end
      ret
    end

    # @param pool_fs [String]
    # @param vps_id [Integer]
    # @yiledparam cfg [VpsConfig::TopLevel]
    def self.create_or_replace(pool_fs, vps_id)
      ret = nil
      cfg = TopLevel.new(pool_fs, vps_id, load: false)
      cfg.lock do
        ret = yield(cfg)
        cfg.save
      end
      ret
    end
  end
end
