module NodeCtld
  module VpsUserData
    class Base
      include OsCtl::Lib::Utils::Log
      include Utils::System
      include Utils::OsCtl
      include Utils::Vps

      # @param vps_id [Integer]
      # @param format [String]
      # @param content [String]
      def self.deploy(*)
        new(*).deploy
      end

      # @param vps_id [Integer]
      # @param format [String]
      # @param content [String]
      # @param os_template [Hash]
      def initialize(vps_id, format, content, os_template)
        @vps_id = vps_id
        @format = format
        @content = content.gsub("\r\n", "\n")
        @os_template = os_template
      end

      def deploy
        raise NotImplementedError
      end
    end
  end
end
