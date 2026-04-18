defmodule Boxart.RenderTest do
  use ExUnit.Case, async: true

  alias Boxart.Graph
  alias Boxart.Graph.{Node, Edge}

  defp graph(direction, edges, node_overrides \\ %{}) do
    node_ids = edges |> Enum.flat_map(fn e -> [e.source, e.target] end) |> Enum.uniq()
    nodes = Map.new(node_ids, fn id -> {id, Map.get(node_overrides, id, Node.new(id))} end)

    %Graph{
      direction: direction,
      nodes: nodes,
      edges: edges,
      node_order: node_ids
    }
  end

  defp simple_edges(pairs) do
    Enum.map(pairs, fn {s, t} -> %Edge{source: s, target: t} end)
  end

  defp labeled_edges(triples) do
    Enum.map(triples, fn {s, t, label} -> %Edge{source: s, target: t, label: label} end)
  end

  describe "basic rendering" do
    test "single chain LR" do
      output =
        graph(:lr, simple_edges([{"A", "B"}, {"B", "C"}]))
        |> Boxart.render()

      for node <- ["A", "B", "C"] do
        assert String.contains?(output, node), "Node #{node} missing"
      end

      assert String.contains?(output, "►") or String.contains?(output, ">")
    end

    test "single chain TD" do
      output =
        graph(:td, simple_edges([{"A", "B"}, {"B", "C"}]))
        |> Boxart.render()

      for node <- ["A", "B", "C"] do
        assert String.contains?(output, node)
      end

      assert String.contains?(output, "▼") or String.contains?(output, "v")
    end

    test "branching TD" do
      output =
        graph(:td, simple_edges([{"A", "B"}, {"A", "C"}]))
        |> Boxart.render()

      for node <- ["A", "B", "C"] do
        assert String.contains?(output, node)
      end
    end

    test "diamond pattern" do
      output =
        graph(:td, simple_edges([{"A", "B"}, {"A", "C"}, {"B", "D"}, {"C", "D"}]))
        |> Boxart.render()

      for node <- ["A", "B", "C", "D"] do
        assert String.contains?(output, node)
      end
    end
  end

  describe "multiline labels" do
    test "newline in label renders both lines" do
      output =
        graph(
          :td,
          simple_edges([{"A", "B"}]),
          %{
            "A" => Node.new("A", label: "Line 1\nLine 2"),
            "B" => Node.new("B", label: "Target")
          }
        )
        |> Boxart.render()

      assert String.contains?(output, "Line 1")
      assert String.contains?(output, "Line 2")
      assert String.contains?(output, "Target")
    end
  end

  describe "edge labels" do
    test "labeled edges show labels" do
      output =
        graph(:lr, labeled_edges([{"A", "B", "yes"}, {"A", "C", "no"}]))
        |> Boxart.render()

      assert String.contains?(output, "yes")
      assert String.contains?(output, "no")
    end
  end

  describe "ASCII mode" do
    test "produces no unicode box-drawing characters" do
      output =
        graph(:lr, simple_edges([{"A", "B"}, {"B", "C"}]))
        |> Boxart.render(charset: :ascii)

      box_chars = ~c[┌┐└┘─│├┤┬┴┼╭╮╰╯►◄▲▼┄┆━┃╋]

      used =
        output
        |> String.graphemes()
        |> Enum.filter(fn ch ->
          <<cp::utf8>> = ch
          cp in box_chars
        end)

      assert used == [], "ASCII mode contains unicode chars: #{inspect(used)}"
    end

    test "renders all nodes" do
      output =
        graph(:lr, simple_edges([{"A", "B"}, {"B", "C"}]))
        |> Boxart.render(charset: :ascii)

      for node <- ["A", "B", "C"] do
        assert String.contains?(output, node)
      end
    end
  end

  describe "rendering quality" do
    test "valid unicode output" do
      output =
        graph(:td, simple_edges([{"A", "B"}, {"B", "C"}]))
        |> Boxart.render()

      refute String.contains?(output, "\uFFFD")
      assert output == output |> String.to_charlist() |> List.to_string()
    end

    test "reasonable dimensions" do
      output =
        graph(:lr, simple_edges([{"A", "B"}, {"B", "C"}]))
        |> Boxart.render()

      lines = String.split(output, "\n")
      assert length(lines) <= 200
      max_width = lines |> Enum.map(&String.length/1) |> Enum.max(fn -> 0 end)
      assert max_width <= 500
    end

    test "all nodes appear in output" do
      edges = simple_edges([{"A", "B"}, {"A", "C"}, {"B", "D"}, {"C", "D"}, {"D", "E"}])
      output = graph(:td, edges) |> Boxart.render()

      for node <- ["A", "B", "C", "D", "E"] do
        assert String.contains?(output, node), "Node #{node} missing from output"
      end
    end
  end

  describe "gap parameter" do
    test "smaller gap produces narrower LR output" do
      edges = simple_edges([{"A", "B"}, {"B", "C"}, {"C", "D"}, {"D", "E"}])
      g = graph(:lr, edges)

      w4 =
        g
        |> Boxart.render(gap: 4)
        |> String.split("\n")
        |> Enum.map(&String.length/1)
        |> Enum.max()

      w1 =
        g
        |> Boxart.render(gap: 1)
        |> String.split("\n")
        |> Enum.map(&String.length/1)
        |> Enum.max()

      assert w1 < w4
    end

    test "gap=0 is clamped to gap=1" do
      edges = simple_edges([{"A", "B"}, {"B", "C"}])
      g = graph(:lr, edges)
      assert Boxart.render(g, gap: 0) == Boxart.render(g, gap: 1)
    end

    test "all nodes visible with compact gap" do
      edges = simple_edges([{"A", "B"}, {"B", "C"}, {"C", "D"}, {"D", "E"}, {"E", "F"}])
      output = graph(:lr, edges) |> Boxart.render(gap: 1)

      for node <- ~w(A B C D E F) do
        assert String.contains?(output, node)
      end
    end
  end

  describe "node shapes" do
    test "diamond shape renders diamond corners" do
      output =
        graph(
          :td,
          simple_edges([{"A", "B"}]),
          %{"A" => Node.new("A", label: "Q?", shape: :diamond)}
        )
        |> Boxart.render()

      assert String.contains?(output, "◇") or String.contains?(output, "/")
    end

    test "rounded shape renders rounded corners" do
      output =
        graph(
          :td,
          simple_edges([{"A", "B"}]),
          %{"A" => Node.new("A", label: "Hi", shape: :rounded)}
        )
        |> Boxart.render()

      assert String.contains?(output, "╭") or String.contains?(output, "+")
    end
  end
end
