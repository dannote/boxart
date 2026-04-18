defmodule Boxart.CodeNodeTest do
  use ExUnit.Case, async: true

  alias Boxart.Canvas
  alias Boxart.Charset
  alias Boxart.CodeNode
  alias Boxart.CodeNode.CodeLabel

  describe "format_label/2" do
    test "splits source into numbered lines" do
      label = CodeNode.format_label("a\nb\nc")

      assert %CodeLabel{height: 3} = label
      assert [{"1", "a"}, {"2", "b"}, {"3", "c"}] = label.lines
    end

    test "respects start_line" do
      label = CodeNode.format_label("x = 1\ny = 2", start_line: 10)

      assert [{"10", "x = 1"}, {"11", "y = 2"}] = label.lines
    end

    test "pads line numbers to same width" do
      source = Enum.map_join(1..12, "\n", &"line#{&1}")
      label = CodeNode.format_label(source, start_line: 1)

      {num_str, _} = hd(label.lines)
      assert String.length(num_str) == 2
      assert String.starts_with?(num_str, " ")
    end

    test "computes width from longest line" do
      label = CodeNode.format_label("short\na much longer line")

      assert label.width >= Boxart.Utils.display_width("a much longer line")
    end

    test "produces highlighted segments with language option" do
      label = CodeNode.format_label("def foo, do: :ok", language: :elixir)

      {_num, code} = hd(label.lines)
      assert is_list(code)
      assert Enum.all?(code, fn {text, style} -> is_binary(text) and is_binary(style) end)
    end

    test "single line source" do
      label = CodeNode.format_label("x = 1")

      assert %CodeLabel{height: 1, lines: [{"1", "x = 1"}]} = label
    end
  end

  describe "render_to_canvas/7" do
    test "draws line numbers and code into canvas" do
      label = CodeNode.format_label("hello\nworld", start_line: 1)
      cs = Charset.unicode()
      canvas = Canvas.new(30, 10)

      canvas = CodeNode.render_to_canvas(canvas, 0, 0, 20, 5, label, cs)
      output = Canvas.to_string(canvas)

      assert String.contains?(output, "1")
      assert String.contains?(output, "2")
      assert String.contains?(output, "hello")
      assert String.contains?(output, "world")
      assert String.contains?(output, "│")
    end
  end

  describe "integration with Boxart.render" do
    test "renders a graph with code nodes" do
      graph =
        Graph.new()
        |> Graph.add_vertex("code",
          source: "x = 1\ny = 2",
          start_line: 5,
          language: :elixir
        )
        |> Graph.add_vertex("next", label: "Next")
        |> Graph.add_edge("code", "next")

      result = Boxart.render(graph)

      assert String.contains?(result, "x = 1")
      assert String.contains?(result, "y = 2")
      assert String.contains?(result, "Next")
    end

    test "renders code node without highlighting" do
      graph =
        Graph.new()
        |> Graph.add_vertex("block", source: "puts 'hello'", start_line: 1)

      result = Boxart.render(graph)
      assert String.contains?(result, "puts 'hello'")
    end
  end
end
