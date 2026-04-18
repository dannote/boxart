defmodule Boxart.EdgeStylesTest do
  use ExUnit.Case, async: true

  alias Boxart.Graph, as: BG
  alias Boxart.Graph.Edge

  defp graph(direction, edges) do
    node_ids = edges |> Enum.flat_map(fn e -> [e.source, e.target] end) |> Enum.uniq()
    nodes = Map.new(node_ids, fn id -> {id, %BG.Node{id: id, label: id}} end)

    %BG{direction: direction, nodes: nodes, edges: edges, node_order: node_ids}
    |> Boxart.Render.render_graph([])
  end

  describe "unicode solid edges" do
    test "unidirectional LR" do
      output = graph(:lr, [%Edge{source: "A", target: "B"}])
      assert String.contains?(output, "─")
      assert String.contains?(output, "►")
    end

    test "unidirectional TD" do
      output = graph(:td, [%Edge{source: "A", target: "B"}])
      assert String.contains?(output, "│")
      assert String.contains?(output, "▼")
    end

    test "bidirectional LR" do
      output =
        graph(:lr, [%Edge{source: "A", target: "B", has_arrow_start: true, has_arrow_end: true}])

      assert String.contains?(output, "◄")
      assert String.contains?(output, "►")
    end

    test "no-arrow LR" do
      output = graph(:lr, [%Edge{source: "A", target: "B", has_arrow_end: false}])
      refute String.contains?(output, "►")
      refute String.contains?(output, "◄")
      assert String.contains?(output, "─")
    end
  end

  describe "unicode dotted edges" do
    test "unidirectional LR" do
      output = graph(:lr, [%Edge{source: "A", target: "B", style: :dotted}])
      assert String.contains?(output, "┄")
      assert String.contains?(output, "►")
    end

    test "unidirectional TD" do
      output = graph(:td, [%Edge{source: "A", target: "B", style: :dotted}])
      assert String.contains?(output, "┆")
      assert String.contains?(output, "▼")
    end
  end

  describe "unicode thick edges" do
    test "unidirectional LR" do
      output = graph(:lr, [%Edge{source: "A", target: "B", style: :thick}])
      assert String.contains?(output, "━")
      assert String.contains?(output, "►")
    end

    test "unidirectional TD" do
      output = graph(:td, [%Edge{source: "A", target: "B", style: :thick}])
      assert String.contains?(output, "┃")
      assert String.contains?(output, "▼")
    end
  end

  describe "mixed edge styles" do
    test "all three styles in one graph" do
      output =
        graph(:lr, [
          %Edge{source: "A", target: "B", style: :solid},
          %Edge{source: "B", target: "C", style: :dotted},
          %Edge{source: "C", target: "D", style: :thick}
        ])

      assert String.contains?(output, "─")
      assert String.contains?(output, "┄")
      assert String.contains?(output, "━")

      for label <- ~w(A B C D) do
        assert String.contains?(output, label)
      end
    end
  end

  describe "ASCII edge styles" do
    test "solid LR" do
      output =
        %BG{
          direction: :lr,
          nodes: %{"A" => %BG.Node{id: "A", label: "A"}, "B" => %BG.Node{id: "B", label: "B"}},
          edges: [%Edge{source: "A", target: "B"}],
          node_order: ["A", "B"]
        }
        |> Boxart.Render.render_graph(charset: :ascii)

      assert String.contains?(output, "-")
      assert String.contains?(output, ">")
    end

    test "dotted LR" do
      output =
        %BG{
          direction: :lr,
          nodes: %{"A" => %BG.Node{id: "A", label: "A"}, "B" => %BG.Node{id: "B", label: "B"}},
          edges: [%Edge{source: "A", target: "B", style: :dotted}],
          node_order: ["A", "B"]
        }
        |> Boxart.Render.render_graph(charset: :ascii)

      assert String.contains?(output, ".")
      assert String.contains?(output, ">")
    end

    test "thick LR" do
      output =
        %BG{
          direction: :lr,
          nodes: %{"A" => %BG.Node{id: "A", label: "A"}, "B" => %BG.Node{id: "B", label: "B"}},
          edges: [%Edge{source: "A", target: "B", style: :thick}],
          node_order: ["A", "B"]
        }
        |> Boxart.Render.render_graph(charset: :ascii)

      assert String.contains?(output, "=")
      assert String.contains?(output, ">")
    end

    test "no unicode chars in ASCII mode" do
      box_chars = ~c[┌┐└┘─│├┤┬┴┼╭╮╰╯►◄▲▼┄┆━┃╋]

      for style <- [:solid, :dotted, :thick] do
        output =
          %BG{
            direction: :lr,
            nodes: %{"A" => %BG.Node{id: "A", label: "A"}, "B" => %BG.Node{id: "B", label: "B"}},
            edges: [%Edge{source: "A", target: "B", style: style}],
            node_order: ["A", "B"]
          }
          |> Boxart.Render.render_graph(charset: :ascii)

        used =
          output
          |> String.to_charlist()
          |> Enum.filter(&(&1 in box_chars))

        assert used == [], "ASCII #{style} contains unicode: #{inspect(used)}"
      end
    end
  end

  describe "labeled edges with styles" do
    test "solid label" do
      output = graph(:lr, [%Edge{source: "A", target: "B", label: "yes"}])
      assert String.contains?(output, "yes")
    end

    test "dotted label" do
      output = graph(:lr, [%Edge{source: "A", target: "B", style: :dotted, label: "maybe"}])
      assert String.contains?(output, "maybe")
    end

    test "TD label" do
      output = graph(:td, [%Edge{source: "A", target: "B", label: "down"}])
      assert String.contains?(output, "down")
      assert String.contains?(output, "▼")
    end

    test "multiple labels from same source" do
      output =
        graph(:td, [
          %Edge{source: "A", target: "B", label: "Yes"},
          %Edge{source: "A", target: "C", label: "No"},
          %Edge{source: "A", target: "D", label: "Maybe"}
        ])

      assert String.contains?(output, "Yes")
      assert String.contains?(output, "No")
      assert String.contains?(output, "Maybe")
    end
  end
end
