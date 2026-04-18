defmodule Boxart.Utils do
  @moduledoc """
  Shared utility functions for terminal rendering.
  """

  @doc """
  Returns the terminal display width of `text`.

  East-Asian wide/fullwidth characters and emoji occupy 2 terminal columns;
  everything else occupies 1.
  """
  @spec display_width(String.t()) :: non_neg_integer()
  def display_width(text) do
    text
    |> String.to_charlist()
    |> Enum.reduce(0, fn cp, w ->
      if :unicode_util.is_wide(cp), do: w + 2, else: w + 1
    end)
  end
end
