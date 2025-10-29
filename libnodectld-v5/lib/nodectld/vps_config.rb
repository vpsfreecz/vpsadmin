module NodeCtld
  module VpsConfig
    # @param vps_id [Integer]
    # @yiledparam cfg [VpsConfig::TopLevel]
    def self.open(vps_id)
      cfg = TopLevel.new(vps_id)

      if block_given?
        ret = yield(cfg)
        cfg.save
        ret
      else
        cfg
      end
    end

    # @param vps_id [Integer]
    # @yiledparam cfg [VpsConfig::TopLevel]
    def self.read(vps_id)
      cfg = TopLevel.new(vps_id)

      if block_given?
        yield(cfg)
      else
        cfg
      end
    end

    # @param vps_id [Integer]
    # @yiledparam cfg [VpsConfig::TopLevel]
    def self.edit(vps_id)
      ret = nil
      cfg = TopLevel.new(vps_id, load: false)
      cfg.lock do
        cfg.load if cfg.exist?
        ret = yield(cfg)
        cfg.save
      end
      ret
    end

    # @param vps_id [Integer]
    # @yiledparam cfg [VpsConfig::TopLevel]
    def self.create_or_replace(vps_id)
      ret = nil
      cfg = TopLevel.new(vps_id, load: false)
      cfg.lock do
        ret = yield(cfg)
        cfg.save
      end
      ret
    end
  end
end
