defmodule Boxart.Highlight do
  @moduledoc """
  ANSI terminal formatter for Makeup syntax highlighting tokens.

  Maps Makeup `{type, metadata, text}` token types to ANSI escape sequences
  using a dark terminal color scheme.
  """

  @reset "\e[0m"

  @keywords ~w[keyword keyword_constant keyword_declaration keyword_namespace
               keyword_pseudo keyword_reserved keyword_type]a

  @functions ~w[name_function name_function_magic name_class name_namespace]a

  @strings ~w[string string_affix string_backtick string_char string_delimeter
              string_doc string_double string_escape string_heredoc string_interpol
              string_other string_regex string_sigil string_single]a

  @numbers ~w[number number_bin number_float number_hex number_integer number_oct]a

  @comments ~w[comment comment_hashbang comment_multiline comment_preproc
               comment_single comment_special]a

  @type styled_segment :: {String.t(), String.t()}

  @doc """
  Tokenizes and formats source code with ANSI colors.

  Returns a list of `{text, ansi_style}` tuples. If Makeup or the requested
  lexer is unavailable, returns the source as-is with an empty style.
  """
  @spec highlight(String.t(), atom()) :: [styled_segment()]
  def highlight(source, language) do
    case lexer_for(language) do
      nil -> [{source, ""}]
      lexer -> do_highlight(lexer, source)
    end
  end

  @doc """
  Converts Makeup tokens to `[{text, style}]` pairs.
  """
  @spec format_tokens([{atom(), keyword(), String.t() | [any()]}]) :: [styled_segment()]
  def format_tokens(tokens) do
    Enum.map(tokens, fn {type, _meta, text} ->
      {IO.iodata_to_binary(List.wrap(text)), ansi_for_type(type)}
    end)
  end

  @doc """
  Returns a single ANSI-colored string for the given source and language.
  """
  @spec to_ansi_string(String.t(), atom()) :: String.t()
  def to_ansi_string(source, language) do
    source
    |> highlight(language)
    |> Enum.map_join(fn
      {text, ""} -> text
      {text, style} -> style <> text <> @reset
    end)
  end

  defp ansi_for_type(t) when t in @keywords, do: "\e[35m"
  defp ansi_for_type(t) when t in @functions, do: "\e[34m"
  defp ansi_for_type(t) when t in @strings, do: "\e[32m"
  defp ansi_for_type(t) when t in @numbers, do: "\e[36m"
  defp ansi_for_type(t) when t in @comments, do: "\e[90m"
  defp ansi_for_type(t) when t in [:operator, :operator_word], do: "\e[33m"
  defp ansi_for_type(t) when t in [:name_atom, :string_symbol], do: "\e[36m"
  defp ansi_for_type(:name_builtin), do: "\e[34m"
  defp ansi_for_type(_), do: ""

  defp do_highlight(lexer, source) do
    tokens = lexer.lex(source)
    format_tokens(tokens)
  end

  defp lexer_for(language) do
    module = lexer_module_for(language)

    if module && Code.ensure_loaded?(Makeup) && Code.ensure_loaded?(module),
      do: module
  end

  defp lexer_module_for(:elixir), do: Makeup.Lexers.ElixirLexer
  defp lexer_module_for(_), do: nil
end
