# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :line_chat,
  generators: [timestamp_type: :utc_datetime]

# Chat behaviour: fixed JST offset for display, and a cap on message bodies.
config :line_chat, :utc_offset, 9 * 3600
config :line_chat, :max_body_length, 500

# Configures the endpoint
config :line_chat, LineChatWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: LineChatWeb.ErrorHTML, json: LineChatWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: LineChat.PubSub,
  live_view: [signing_salt: "e4iDywOc"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  line_chat: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
