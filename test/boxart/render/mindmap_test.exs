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
end
