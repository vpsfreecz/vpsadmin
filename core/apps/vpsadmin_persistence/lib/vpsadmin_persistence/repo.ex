defmodule VpsAdmin.Persistence.Repo do
  use Ecto.Repo, otp_app: :vpsadmin_persistence, adapter: Ecto.Adapters.MySQL
end
