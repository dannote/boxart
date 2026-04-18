defmodule BoxartTest do
  use ExUnit.Case

  alias Boxart.Render.Mindmap

  test "render returns empty string for empty graph" do
    graph = Graph.new()
    assert Boxart.render(graph) == ""
  end

  test "render returns a string for a simple graph" do
    graph =
      Graph.new()
      |> Graph.add_vertex("A", label: "Hello")
      |> Graph.add_vertex("B", label: "World")
      |> Graph.add_edge("A", "B")

    result = Boxart.render(graph)
    assert is_binary(result)
    assert String.contains?(result, "Hello")
    assert String.contains?(result, "World")
  end

  test "render supports ascii charset" do
    graph =
      Graph.new()
      |> Graph.add_vertex("A", label: "Test")

    result = Boxart.render(graph, charset: :ascii)
    assert is_binary(result)
    assert String.contains?(result, "Test")
    refute String.contains?(result, "┌")
  end

  test "render with direction option" do
    graph =
      Graph.new()
      |> Graph.add_vertex("A", label: "Start")
      |> Graph.add_vertex("B", label: "End")
      |> Graph.add_edge("A", "B")

    lr = Boxart.render(graph, direction: :lr)
    td = Boxart.render(graph, direction: :td)

    assert String.contains?(lr, "Start")
    assert String.contains?(td, "Start")
    assert lr != td
  end

  test "render with node shapes" do
    graph =
      Graph.new()
      |> Graph.add_vertex("A", label: "Question?", shape: :diamond)
      |> Graph.add_vertex("B", label: "Answer")
      |> Graph.add_edge("A", "B")

    result = Boxart.render(graph)
    assert String.contains?(result, "Question?")
    assert String.contains?(result, "◇") or String.contains?(result, "/")
  end

  test "render with edge labels" do
    graph =
      Graph.new()
      |> Graph.add_vertex("A", label: "Start")
      |> Graph.add_vertex("B", label: "End")
      |> Graph.add_edge("A", "B", label: "next")

    result = Boxart.render(graph, direction: :td)
    assert String.contains?(result, "next")
  end

  test "render with atom vertices" do
    graph =
      Graph.new()
      |> Graph.add_vertex(:hello, label: "Hello")
      |> Graph.add_vertex(:world, label: "World")
      |> Graph.add_edge(:hello, :world)

    result = Boxart.render(graph)
    assert String.contains?(result, "Hello")
    assert String.contains?(result, "World")
  end

  test "vertex without label uses inspect of vertex" do
    graph =
      Graph.new()
      |> Graph.add_vertex(:foo)
      |> Graph.add_vertex(:bar)
      |> Graph.add_edge(:foo, :bar)

    result = Boxart.render(graph)
    assert String.contains?(result, "foo")
    assert String.contains?(result, "bar")
  end

  test "edge keyword labels with style" do
    g =
      Graph.new()
      |> Graph.add_vertex("A")
      |> Graph.add_vertex("B")
      |> Graph.add_edge("A", "B", label: [label: "link", style: :dotted])

    result = Boxart.render(g, direction: :lr)
    assert String.contains?(result, "link")
    assert String.contains?(result, "┄")
  end

  test "edge keyword labels with bidirectional" do
    g =
      Graph.new()
      |> Graph.add_vertex("A")
      |> Graph.add_vertex("B")
      |> Graph.add_edge("A", "B", label: [bidirectional: true])

    result = Boxart.render(g, direction: :lr)
    assert String.contains?(result, "◄")
    assert String.contains?(result, "►")
  end

  test "edge keyword labels with no arrow" do
    g =
      Graph.new()
      |> Graph.add_vertex("A")
      |> Graph.add_vertex("B")
      |> Graph.add_edge("A", "B", label: [arrow: false])

    result = Boxart.render(g, direction: :lr)
    refute String.contains?(result, "►")
    assert String.contains?(result, "┤") or String.contains?(result, "├")
  end

  test "max_width truncates output" do
    g =
      Graph.new()
      |> Graph.add_vertex("A", label: "Alpha")
      |> Graph.add_vertex("B", label: "Beta")
      |> Graph.add_vertex("C", label: "Gamma")
      |> Graph.add_edge("A", "B")
      |> Graph.add_edge("A", "C")

    out = Boxart.render(g, direction: :td, max_width: 25)
    max_w = out |> String.split("\n") |> Enum.map(&String.length/1) |> Enum.max()
    assert max_w <= 25
  end

  test "max_label_width controls word wrapping" do
    g =
      Graph.new()
      |> Graph.add_vertex("A", label: "A short")
      |> Graph.add_vertex("B", label: "A much longer label here")
      |> Graph.add_edge("A", "B")

    narrow = Boxart.render(g, direction: :td, max_label_width: 10)
    wide = Boxart.render(g, direction: :td, max_label_width: 40)

    narrow_w =
      narrow |> String.split("\n") |> Enum.map(&String.length/1) |> Enum.max()

    wide_w =
      wide |> String.split("\n") |> Enum.map(&String.length/1) |> Enum.max()

    assert narrow_w < wide_w
  end

  test "max_width compacts gap and padding before clamping" do
    g =
      Graph.new()
      |> Graph.add_vertex("A", label: "Alpha Node")
      |> Graph.add_vertex("B", label: "Beta Node")
      |> Graph.add_vertex("C", label: "Gamma Node")
      |> Graph.add_vertex("D", label: "Delta Node")
      |> Graph.add_edge("A", "B")
      |> Graph.add_edge("A", "C")
      |> Graph.add_edge("A", "D")

    full = Boxart.render(g, direction: :td)
    compact = Boxart.render(g, direction: :td, max_width: 40)

    full_w = full |> String.split("\n") |> Enum.map(&String.length/1) |> Enum.max()
    compact_w = compact |> String.split("\n") |> Enum.map(&String.length/1) |> Enum.max()

    assert compact_w <= 40
    assert compact_w <= full_w
  end

  test "max_width stacks siblings vertically when needed" do
    g =
      Graph.new()
      |> Graph.add_vertex("root", source: "if condition do", start_line: 1)
      |> Graph.add_vertex("a", source: "long_function_call(arg1, arg2)", start_line: 2)
      |> Graph.add_vertex("b", source: "another_long_call(x, y, z)", start_line: 3)
      |> Graph.add_edge("root", "a")
      |> Graph.add_edge("root", "b")

    out = Boxart.render(g, direction: :td, max_width: 50)
    assert String.contains?(out, "long_function_call")
    assert String.contains?(out, "another_long_call")
  end

  test "Canvas.clamp_width drops cells beyond limit" do
    canvas =
      Boxart.Canvas.new(20, 3)
      |> Boxart.Canvas.put(5, 1, "A")
      |> Boxart.Canvas.put(15, 1, "B")

    clamped = Boxart.Canvas.clamp_width(canvas, 10)
    assert clamped.width == 10
    rendered = Boxart.Canvas.render(clamped)
    assert String.contains?(rendered, "A")
    refute String.contains?(rendered, "B")
  end

  test "mindmap handles tuple vertices without crash" do
    g =
      Graph.new()
      |> Graph.add_vertex({:mod, :fun, 1}, label: "fun/1")
      |> Graph.add_vertex({:mod, :dep, 0}, label: "dep/0")
      |> Graph.add_edge({:mod, :fun, 1}, {:mod, :dep, 0})

    out = Mindmap.render(g)
    assert String.contains?(out, "fun/1")
    assert String.contains?(out, "dep/0")
  end
end
