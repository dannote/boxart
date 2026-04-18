defmodule Boxart.HighlightTest do
  use ExUnit.Case, async: true

  alias Boxart.Highlight

  describe "highlight/2" do
    test "returns styled segments for Elixir code" do
      segments = Highlight.highlight("x = 1", :elixir)

      assert is_list(segments)
      assert segments != []

      full_text = segments |> Enum.map_join(&elem(&1, 0))
      assert full_text == "x = 1"
    end

    test "returns unstyled fallback for unknown language" do
      assert Highlight.highlight("hello", :brainfuck) == [{"hello", ""}]
    end

    test "keywords get magenta" do
      segments = Highlight.highlight("def foo", :elixir)
      {_text, style} = Enum.find(segments, fn {_, s} -> s == "\e[35m" end)
      assert style == "\e[35m"
    end

    test "strings get green" do
      segments = Highlight.highlight(~s("hello"), :elixir)
      styles = Enum.map(segments, &elem(&1, 1)) |> Enum.uniq()
      assert "\e[32m" in styles
    end

    test "numbers get cyan" do
      segments = Highlight.highlight("42", :elixir)
      {_text, style} = Enum.find(segments, fn {_, s} -> s == "\e[36m" end)
      assert style == "\e[36m"
    end
  end

  describe "format_tokens/1" do
    test "converts token tuples to styled pairs" do
      tokens = [{:keyword, %{}, "def"}, {:whitespace, %{}, " "}, {:name_function, %{}, "foo"}]
      result = Highlight.format_tokens(tokens)

      assert [{"def", "\e[35m"}, {" ", ""}, {"foo", "\e[34m"}] = result
    end
  end

  describe "to_ansi_string/2" do
    test "returns a string with ANSI codes" do
      result = Highlight.to_ansi_string("x = 1", :elixir)
      assert is_binary(result)
      assert String.contains?(result, "x")
      assert String.contains?(result, "1")
    end

    test "returns plain text for unknown language" do
      assert Highlight.to_ansi_string("hello", :unknown) == "hello"
    end
  end
end
