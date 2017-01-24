module VpsAdmin::API::Resources
  Location::Index.auth false
  Location::Index.authorize do |u|
    allow if u && u.role == :admin
    output whitelist: %i(id label environment)
    allow
  end

  OsTemplate::Index.auth false
  OsTemplate::Index.authorize do |u|
    allow if u && u.role == :admin

    if u
      restrict enabled: true
      output whitelist: %i(id label info supported)

    else
      restrict enabled: true, supported: true
      output whitelist: %i(id label)
    end

    allow
  end

  Language::Index.auth false
end
