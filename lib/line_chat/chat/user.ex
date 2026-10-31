defmodule LineChat.Chat.User do
  @moduledoc """
  A chat participant. LINE-style apps show an avatar tile plus a display name.
  """

  defstruct [:id, :name, :color, :avatar_char]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          color: String.t(),
          avatar_char: String.t()
        }

  @default_color "#06c755"

  @doc """
  Builds a user, deriving the avatar tile character from the display name.
  """
  def new(id, name, color \\ @default_color) when is_binary(id) and is_binary(name) do
    %__MODULE__{
      id: id,
      name: name,
      color: color,
      avatar_char: avatar_char(name)
    }
  end

  @doc """
  The single character shown inside an avatar tile, `?` for an empty name.
  """
  def avatar_char(name) when is_binary(name) do
    case String.graphemes(name) do
      [first | _] -> first
      [] -> "?"
    end
  end
end
