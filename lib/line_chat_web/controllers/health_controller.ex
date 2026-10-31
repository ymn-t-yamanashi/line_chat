defmodule LineChatWeb.HealthController do
  @moduledoc """
  Liveness endpoint for the read-only API. Reports whether the chat store is
  reachable, which is enough for monitoring and for smoke tests.
  """

  use LineChatWeb, :controller

  alias LineChat.Chat.Store

  def index(conn, _params) do
    json(conn, %{status: "ok", rooms: length(Store.list_rooms())})
  end
end
