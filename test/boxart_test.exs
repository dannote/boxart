defmodule BoxartTest do
  use ExUnit.Case

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
end
