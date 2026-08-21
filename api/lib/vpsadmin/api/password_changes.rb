module VpsAdmin::API
  module PasswordChanges
    SOURCES = %i[
      authenticated
      forced_reset
      recovery
      administrator
      other
    ].freeze
  end
end
