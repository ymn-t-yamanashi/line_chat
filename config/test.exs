import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :line_chat, LineChatWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "jAzQiNqIP/V9kuQ1oikUphTUI1cNygrwC0ENbyAwwi8L2HB0USn6poLVnIWXmBAL",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# The lib forms intentionally rely on the input's own id for recovery, so the
# "form missing id" test warning would fire on every mount. Ignore it in tests.
config :phoenix_live_view, :test_warnings, missing_form_id: :ignore
