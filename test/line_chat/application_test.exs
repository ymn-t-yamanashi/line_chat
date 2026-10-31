defmodule LineChat.ApplicationTest do
  @moduledoc """
  Covers the application callbacks Phoenix invokes outside a request cycle:
  the supervision tree it builds and the config reload it forwards.
  """

  use ExUnit.Case, async: false

  test "config_change/3 forwards the endpoint update and keeps the tree alive" do
    secret_before = LineChatWeb.Endpoint.config(:secret_key_base)

    assert LineChat.Application.config_change(%{}, nil, %{}) == :ok
    assert is_pid(Process.whereis(LineChat.Supervisor))
    assert Process.whereis(LineChatWeb.Telemetry) |> is_pid()
    assert LineChatWeb.Endpoint.config(:secret_key_base) == secret_before
  end
end
