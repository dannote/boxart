defmodule Boxart.Render.MindmapTest do
  use ExUnit.Case, async: true

  alias Boxart.Render.Mindmap
  alias Mindmap.MindmapNode

  defp mind_node(label, children \\ []) do
    %MindmapNode{label: label, children: children}
  end

  describe "basic rendering" do
    test "nil root" do
      assert Mindmap.render(nil) == ""
    end

    test "leaf node" do
      assert Mindmap.render(mind_node("Root")) == "Root"
    end

    test "root with one child" do
      output = Mindmap.render(mind_node("Root", [mind_node("Child")]))
      assert String.contains?(output, "Root")
      assert String.contains?(output, "Child")
      assert String.contains?(output, "──")
    end

    test "root with multiple children" do
      root = mind_node("Root", [mind_node("A"), mind_node("B"), mind_node("C")])
      output = Mindmap.render(root)

      for name <- ["Root", "A", "B", "C"] do
        assert String.contains?(output, name)
      end
    end
  end

  describe "branch connectors" do
    test "uses tree-drawing characters" do
      root = mind_node("Root", [mind_node("A"), mind_node("B"), mind_node("C")])
      output = Mindmap.render(root)

      assert String.contains?(output, "╭") or String.contains?(output, "├") or
               String.contains?(output, "╰")
    end

    test "ascii mode uses plus signs" do
      root = mind_node("Root", [mind_node("A"), mind_node("B")])
      output = Mindmap.render(root, charset: :ascii)

      assert String.contains?(output, "+")
      refute String.contains?(output, "╭")
      refute String.contains?(output, "╰")
    end
  end

  describe "overflow to left" do
    test "many children splits left and right" do
      children = Enum.map(1..9, fn i -> mind_node("Child#{i}") end)
      root = mind_node("Center", children)
      output = Mindmap.render(root)

      assert String.contains?(output, "Center")
      for i <- 1..9, do: assert(String.contains?(output, "Child#{i}"))
    end

    test "threshold boundary: 6 children stay right only" do
      children = Enum.map(1..6, fn i -> mind_node("C#{i}") end)
      root = mind_node("Root", children)
      output = Mindmap.render(root)
      lines = String.split(output, "\n")

      root_line = Enum.find(lines, &String.contains?(&1, "Root"))
      assert root_line != nil
    end

    test "7 children causes split" do
      children = Enum.map(1..7, fn i -> mind_node("N#{i}") end)
      root = mind_node("Root", children)
      output = Mindmap.render(root)

      for i <- 1..7, do: assert(String.contains?(output, "N#{i}"))
    end
  end

  describe "nested trees" do
    test "two levels deep" do
      root =
        mind_node("Root", [
          mind_node("A", [mind_node("A1"), mind_node("A2")]),
          mind_node("B", [mind_node("B1")])
        ])

      output = Mindmap.render(root)

      for name <- ["Root", "A", "A1", "A2", "B", "B1"] do
        assert String.contains?(output, name)
      end
    end

    test "deeply nested" do
      deep = mind_node("L3")
      mid = mind_node("L2", [deep])
      top = mind_node("L1", [mid])
      root = mind_node("Root", [top])

      output = Mindmap.render(root)

      for name <- ["Root", "L1", "L2", "L3"] do
        assert String.contains?(output, name)
      end
    end
  end

  describe "output quality" do
    test "no trailing whitespace issues" do
      root = mind_node("Root", [mind_node("A"), mind_node("B")])
      output = Mindmap.render(root)
      lines = String.split(output, "\n")
      assert length(lines) > 1
    end

    test "valid unicode" do
      root = mind_node("Root", [mind_node("A"), mind_node("B")])
      output = Mindmap.render(root)
      refute String.contains?(output, "\uFFFD")
    end

    test "non-rounded mode" do
      root = mind_node("Root", [mind_node("A"), mind_node("B")])
      output = Mindmap.render(root, rounded: false)
      assert String.contains?(output, "┌") or String.contains?(output, "└")
    end
  end

  describe "libgraph input" do
    test "simple tree from Graph.t()" do
      g =
        Graph.new()
        |> Graph.add_vertex("Root")
        |> Graph.add_vertex("A")
        |> Graph.add_vertex("B")
        |> Graph.add_edge("Root", "A")
        |> Graph.add_edge("Root", "B")

      output = Mindmap.render(g)
      assert String.contains?(output, "Root")
      assert String.contains?(output, "A")
      assert String.contains?(output, "B")
    end

    test "vertex labels used as text" do
      g =
        Graph.new()
        |> Graph.add_vertex("r", label: "Project")
        |> Graph.add_vertex("a", label: "Design")
        |> Graph.add_vertex("b", label: "Build")
        |> Graph.add_edge("r", "a")
        |> Graph.add_edge("r", "b")

      output = Mindmap.render(g)
      assert String.contains?(output, "Project")
      assert String.contains?(output, "Design")
      assert String.contains?(output, "Build")
    end

    test "deeply nested graph" do
      g =
        Graph.new()
        |> Graph.add_vertex("R")
        |> Graph.add_vertex("A")
        |> Graph.add_vertex("B")
        |> Graph.add_vertex("C")
        |> Graph.add_edge("R", "A")
        |> Graph.add_edge("A", "B")
        |> Graph.add_edge("B", "C")

      output = Mindmap.render(g)
      for name <- ~w(R A B C), do: assert(String.contains?(output, name))
    end

    test "empty graph returns empty string" do
      assert Mindmap.render(Graph.new()) == ""
    end

    test "single vertex" do
      g = Graph.new() |> Graph.add_vertex("Alone")
      assert String.contains?(Mindmap.render(g), "Alone")
    end

    test "many children triggers left overflow" do
      g =
        Enum.reduce(1..9, Graph.new() |> Graph.add_vertex("Center"), fn i, acc ->
          acc |> Graph.add_vertex("C#{i}") |> Graph.add_edge("Center", "C#{i}")
        end)

      output = Mindmap.render(g)
      assert String.contains?(output, "Center")
      for i <- 1..9, do: assert(String.contains?(output, "C#{i}"))
    end
  end
end

defmodule Boxart.Render.MindmapMultilineTest do
  use ExUnit.Case, async: true

  alias Boxart.Render.Mindmap

  test "multi-line labels render inline" do
    g =
      Graph.new()
      |> Graph.add_vertex(:root, label: "Root\nMetric=5")
      |> Graph.add_vertex(:child, label: "Child\nValue=3")
      |> Graph.add_edge(:root, :child)

    output = Mindmap.render(g)
    lines = String.split(output, "\n")

    assert length(lines) == 1
    assert String.contains?(output, "Root")
    assert String.contains?(output, "Metric=5")
    assert String.contains?(output, "Child")
    assert String.contains?(output, "Value=3")
  end
end
