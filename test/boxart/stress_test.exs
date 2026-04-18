defmodule Boxart.StressTest do
  use ExUnit.Case, async: true

  alias Boxart.Graph, as: BG
  alias Boxart.Graph.Edge

  defp chain(direction, count) do
    ids = Enum.map(0..(count - 1), &"N#{&1}")
    nodes = Map.new(ids, fn id -> {id, %BG.Node{id: id, label: id}} end)

    edges =
      ids
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [a, b] -> %Edge{source: a, target: b} end)

    %BG{direction: direction, nodes: nodes, edges: edges, node_order: ids}
    |> Boxart.Render.render_graph([])
  end

  defp fan(direction, source, targets) do
    all = [source | targets]
    nodes = Map.new(all, fn id -> {id, %BG.Node{id: id, label: id}} end)
    edges = Enum.map(targets, fn t -> %Edge{source: source, target: t} end)

    %BG{direction: direction, nodes: nodes, edges: edges, node_order: all}
    |> Boxart.Render.render_graph([])
  end

  describe "wide graphs" do
    test "10-node chain LR" do
      output = chain(:lr, 10)

      for i <- 0..9 do
        assert String.contains?(output, "N#{i}")
      end
    end

    test "10-node chain TD" do
      output = chain(:td, 10)

      for i <- 0..9 do
        assert String.contains?(output, "N#{i}")
      end
    end
  end

  describe "fan-out" do
    test "5 targets" do
      output = fan(:td, "A", ~w(B C D E F))

      for label <- ~w(A B C D E F) do
        assert String.contains?(output, label)
      end
    end
  end

  describe "fan-in" do
    test "5 sources to one target" do
      nodes = Map.new(~w(A B C D E F), fn id -> {id, %BG.Node{id: id, label: id}} end)
      edges = Enum.map(~w(A B C D E), fn s -> %Edge{source: s, target: "F"} end)

      output =
        %BG{direction: :td, nodes: nodes, edges: edges, node_order: ~w(A B C D E F)}
        |> Boxart.Render.render_graph([])

      for label <- ~w(A B C D E F) do
        assert String.contains?(output, label)
      end
    end
  end

  describe "100-node chain" do
    test "LR renders without crash" do
      output = chain(:lr, 100)
      assert String.contains?(output, "N0")
      assert String.contains?(output, "N99")
    end

    test "TD renders without crash" do
      output = chain(:td, 100)
      assert String.contains?(output, "N0")
      assert String.contains?(output, "N99")
    end
  end

  describe "very long labels" do
    test "50-char label" do
      label = String.duplicate("A", 50)

      output =
        %BG{
          direction: :td,
          nodes: %{
            "X" => %BG.Node{id: "X", label: label},
            "Y" => %BG.Node{id: "Y", label: "Y"}
          },
          edges: [%Edge{source: "X", target: "Y"}],
          node_order: ["X", "Y"]
        }
        |> Boxart.Render.render_graph([])

      assert String.contains?(output, "Y")
    end

    test "100-char label" do
      label = String.duplicate("B", 100)

      output =
        %BG{
          direction: :td,
          nodes: %{
            "X" => %BG.Node{id: "X", label: label},
            "Y" => %BG.Node{id: "Y", label: "Y"}
          },
          edges: [%Edge{source: "X", target: "Y"}],
          node_order: ["X", "Y"]
        }
        |> Boxart.Render.render_graph([])

      assert String.contains?(output, "Y")
    end
  end

  describe "emoji labels" do
    test "emoji in vertex renders" do
      output =
        %BG{
          direction: :lr,
          nodes: %{
            "A" => %BG.Node{id: "A", label: "Start 🚀"},
            "B" => %BG.Node{id: "B", label: "Done ✅"}
          },
          edges: [%Edge{source: "A", target: "B"}],
          node_order: ["A", "B"]
        }
        |> Boxart.Render.render_graph([])

      assert is_binary(output)
      assert String.contains?(output, "Start")
      assert String.contains?(output, "Done")
    end
  end

  describe "disconnected nodes" do
    test "4 isolated nodes all render" do
      nodes = Map.new(~w(A B C D), fn id -> {id, %BG.Node{id: id, label: id}} end)

      output =
        %BG{direction: :td, nodes: nodes, edges: [], node_order: ~w(A B C D)}
        |> Boxart.Render.render_graph([])

      for n <- ~w(A B C D) do
        assert String.contains?(output, n)
      end
    end
  end

  describe "self-loop" do
    test "renders without crash" do
      output =
        %BG{
          direction: :td,
          nodes: %{"A" => %BG.Node{id: "A", label: "A"}},
          edges: [%Edge{source: "A", target: "A"}],
          node_order: ["A"]
        }
        |> Boxart.Render.render_graph([])

      assert String.contains?(output, "A")
      assert length(String.split(output, "\n")) > 1
    end

    test "self-loop with label" do
      output =
        %BG{
          direction: :td,
          nodes: %{"A" => %BG.Node{id: "A", label: "A"}},
          edges: [%Edge{source: "A", target: "A", label: "retry"}],
          node_order: ["A"]
        }
        |> Boxart.Render.render_graph([])

      assert String.contains?(output, "retry")
    end
  end

  describe "cycles" do
    test "3-node cycle renders with reasonable height" do
      output =
        %BG{
          direction: :lr,
          nodes: Map.new(~w(A B C), fn id -> {id, %BG.Node{id: id, label: id}} end),
          edges: [
            %Edge{source: "A", target: "B"},
            %Edge{source: "B", target: "C"},
            %Edge{source: "C", target: "A"}
          ],
          node_order: ~w(A B C)
        }
        |> Boxart.Render.render_graph([])

      for label <- ~w(A B C) do
        assert String.contains?(output, label)
      end

      lines = String.split(output, "\n")
      assert length(lines) < 50, "Cycle output too tall: #{length(lines)} lines"
    end

    test "4-node cycle renders with reasonable height" do
      output =
        %BG{
          direction: :td,
          nodes: Map.new(~w(A B C D), fn id -> {id, %BG.Node{id: id, label: id}} end),
          edges: [
            %Edge{source: "A", target: "B"},
            %Edge{source: "B", target: "C"},
            %Edge{source: "C", target: "D"},
            %Edge{source: "D", target: "A"}
          ],
          node_order: ~w(A B C D)
        }
        |> Boxart.Render.render_graph([])

      lines = String.split(output, "\n")
      assert length(lines) < 50, "Cycle output too tall: #{length(lines)} lines"
    end
  end

  describe "multiple edges same pair" do
    test "renders without crash" do
      output =
        %BG{
          direction: :lr,
          nodes: %{"A" => %BG.Node{id: "A", label: "A"}, "B" => %BG.Node{id: "B", label: "B"}},
          edges: [
            %Edge{source: "A", target: "B"},
            %Edge{source: "A", target: "B"},
            %Edge{source: "A", target: "B"}
          ],
          node_order: ["A", "B"]
        }
        |> Boxart.Render.render_graph([])

      assert String.contains?(output, "A")
      assert String.contains?(output, "B")
    end
  end

  describe "mixed shapes and styles" do
    test "comprehensive graph" do
      nodes =
        Map.new(
          [
            {"A", :rectangle, "Rect"},
            {"B", :rounded, "Round"},
            {"C", :diamond, "Diam"},
            {"D", :stadium, "Stad"},
            {"E", :hexagon, "Hex"},
            {"F", :circle, "Circ"}
          ],
          fn {id, shape, label} -> {id, %BG.Node{id: id, label: label, shape: shape}} end
        )

      edges = [
        %Edge{source: "A", target: "B", style: :solid},
        %Edge{source: "B", target: "C", style: :dotted},
        %Edge{source: "C", target: "D", style: :thick},
        %Edge{source: "D", target: "E"},
        %Edge{source: "E", target: "F"},
        %Edge{source: "F", target: "A", label: "loop"}
      ]

      output =
        %BG{direction: :td, nodes: nodes, edges: edges, node_order: ~w(A B C D E F)}
        |> Boxart.Render.render_graph([])

      for label <- ~w(Rect Round Diam Stad Hex Circ) do
        assert String.contains?(output, label)
      end

      assert String.contains?(output, "loop")
    end
  end

  describe "diamond with multiple outputs" do
    test "3-way decision" do
      nodes = %{
        "A" => %BG.Node{id: "A", label: "Decision", shape: :diamond},
        "B" => %BG.Node{id: "B", label: "Yes"},
        "C" => %BG.Node{id: "C", label: "No"},
        "D" => %BG.Node{id: "D", label: "Maybe"}
      }

      edges = [
        %Edge{source: "A", target: "B", label: "Yes"},
        %Edge{source: "A", target: "C", label: "No"},
        %Edge{source: "A", target: "D", label: "Maybe"}
      ]

      output =
        %BG{direction: :td, nodes: nodes, edges: edges, node_order: ~w(A B C D)}
        |> Boxart.Render.render_graph([])

      assert String.contains?(output, "Decision")
      assert String.contains?(output, "Yes")
      assert String.contains?(output, "No")
      assert String.contains?(output, "Maybe")
    end
  end
end
