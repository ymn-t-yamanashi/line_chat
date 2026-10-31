defmodule LineChatWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use LineChatWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  alias LineChat.Chat.{Seeder, Store}

  using do
    quote do
      # The default endpoint for testing
      @endpoint LineChatWeb.Endpoint

      use LineChatWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import LineChatWeb.ConnCase
    end
  end

  setup _tags do
    # The chat store is a single in-memory process, so every test starts from
    # the same seeded demo transcript and runs with async: false.
    Store.reset()
    {:ok, _seeded} = Seeder.seed()
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
