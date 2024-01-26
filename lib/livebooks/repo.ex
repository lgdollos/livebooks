defmodule Livebooks.Repo do
  use Ecto.Repo,
    otp_app: :livebooks,
    adapter: Ecto.Adapters.Postgres
end
