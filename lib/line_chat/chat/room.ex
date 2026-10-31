defmodule LineChat.Chat.Room do
  @moduledoc """
  A chat room, mirroring a LINE group or a one-to-one chat thread.
  """

  defstruct [:id, :name, :member_ids, created_at: nil]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          member_ids: [String.t()],
          created_at: DateTime.t() | nil
        }

  @doc """
  Builds a room from validated input. Member ids are de-duplicated, keeping order.
  """
  def new(id, name, member_ids, created_at \\ nil)
      when is_binary(id) and is_binary(name) and is_list(member_ids) do
    %__MODULE__{
      id: id,
      name: name,
      member_ids: Enum.uniq(member_ids),
      created_at: created_at
    }
  end

  @doc """
  Returns true when the given user belongs to the room.
  """
  def member?(%__MODULE__{member_ids: member_ids}, user_id) when is_binary(user_id) do
    user_id in member_ids
  end

  @doc """
  Adds a member, returning the room unchanged when the user already joined.
  """
  def add_member(%__MODULE__{member_ids: member_ids} = room, user_id) when is_binary(user_id) do
    %{room | member_ids: (member_ids ++ [user_id]) |> Enum.uniq()}
  end

  @doc """
  Removes a member. Other members are untouched.
  """
  def remove_member(%__MODULE__{member_ids: member_ids} = room, user_id)
      when is_binary(user_id) do
    %{room | member_ids: List.delete(member_ids, user_id)}
  end
end
