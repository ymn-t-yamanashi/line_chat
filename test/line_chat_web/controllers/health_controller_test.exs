defmodule LineChatWeb.HealthControllerTest do
  @moduledoc """
  `GET /api/health` reports liveness plus the room count straight from the store.
  """

  use LineChatWeb.ConnCase, async: false

  alias LineChat.Chat
  alias LineChat.Chat.{Seeder, Store}

  defp health_get(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> get(~p"/api/health")
  end

  defp payload(conn) do
    Jason.decode!(conn.resp_body)
  end

  defp content_type(conn) do
    conn.resp_headers |> List.keyfind("content-type", 0) |> elem(1) |> String.split(";") |> hd()
  end

  test "reports ok with the seeded room count", %{conn: conn} do
    assert payload(health_get(conn)) == %{"status" => "ok", "rooms" => 3}
  end

  test "counts exactly the rooms held by the store", %{conn: conn} do
    assert payload(health_get(conn))["rooms"] == length(Store.list_rooms())
  end

  test "answers 200 as json", %{conn: conn} do
    response = health_get(conn)

    assert response.status == 200
    assert content_type(response) == "application/json"
  end

  test "reports zero when the store is emptied", %{conn: conn} do
    :ok = Store.reset()

    assert payload(health_get(conn)) == %{"status" => "ok", "rooms" => 0}
  end

  test "counts rooms created after startup", %{conn: conn} do
    {:ok, member} = Chat.add_user("追加メンバー")
    {:ok, _room} = Chat.create_room("新しい部屋", [member.id])

    assert payload(health_get(conn))["rooms"] == 4
  end

  test "counts seeded rooms regardless of who joined them", %{conn: conn} do
    {:ok, guest} = Chat.create_guest_user()

    assert payload(health_get(conn)) == %{"status" => "ok", "rooms" => length(Store.list_rooms())}
    assert Chat.list_rooms(guest.id) |> length() == Seeder.room_names() |> length()
  end

  test "reports the same count twice in a row", %{conn: conn} do
    assert payload(health_get(conn)) == payload(health_get(conn))
  end
end
