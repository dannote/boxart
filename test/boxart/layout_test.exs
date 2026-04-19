defmodule Boxart.LayoutTest do
  use ExUnit.Case, async: true

  alias Boxart.Graph
  alias Boxart.Graph.{Edge, Node}
  alias Boxart.Layout

  defp graph(direction, edges, extra_nodes \\ []) do
    node_ids =
      edges
      |> Enum.flat_map(fn {s, t} -> [s, t] end)
      |> Enum.concat(extra_nodes)
      |> Enum.uniq()

    nodes = Map.new(node_ids, fn id -> {id, Node.new(id)} end)
    edge_structs = Enum.map(edges, fn {s, t} -> %Edge{source: s, target: t} end)

    %Graph{
      direction: direction,
      nodes: nodes,
      edges: edge_structs,
      node_order: node_ids
    }
  end

  describe "layer assignment" do
    test "single node" do
      g = graph(:lr, [], ["A"])
      layout = Layout.compute_layout(g)
      assert Map.has_key?(layout.placements, "A")
    end

    test "chain nodes are in successive layers" do
      g = graph(:lr, [{"A", "B"}, {"B", "C"}])
      layout = Layout.compute_layout(g)
      pa = layout.placements["A"]
      pb = layout.placements["B"]
      pc = layout.placements["C"]
      assert pa.grid.col < pb.grid.col
      assert pb.grid.col < pc.grid.col
    end

    test "children of same parent are in the same layer" do
      g = graph(:lr, [{"A", "B"}, {"A", "C"}])
      layout = Layout.compute_layout(g)
      pb = layout.placements["B"]
      pc = layout.placements["C"]
      assert pb.grid.col == pc.grid.col
    end

    test "TD layers map to rows" do
      g = graph(:td, [{"A", "B"}, {"B", "C"}])
      layout = Layout.compute_layout(g)
      pa = layout.placements["A"]
      pb = layout.placements["B"]
      pc = layout.placements["C"]
      assert pa.grid.row < pb.grid.row
      assert pb.grid.row < pc.grid.row
    end
  end

  describe "grid placement" do
    test "no two nodes overlap" do
      g = graph(:lr, [{"A", "B"}, {"A", "C"}, {"B", "D"}, {"C", "D"}])
      layout = Layout.compute_layout(g)

      blocks =
        layout.placements
        |> Map.values()
        |> Enum.map(fn p ->
          for dc <- -1..1, dr <- -1..1, into: MapSet.new(), do: {p.grid.col + dc, p.grid.row + dr}
        end)

      for {b1, i} <- Enum.with_index(blocks),
          {b2, j} <- Enum.with_index(blocks),
          i < j do
        assert MapSet.disjoint?(b1, b2), "Nodes overlap"
      end
    end

    test "cycle does not cause excessive grid positions" do
      g = graph(:lr, [{"A", "B"}, {"B", "C"}, {"C", "A"}])
      layout = Layout.compute_layout(g)

      Enum.each(layout.placements, fn {_nid, p} ->
        assert p.grid.col < 50
        assert p.grid.row < 50
      end)
    end

    test "all nodes are placed" do
      g = graph(:lr, [{"A", "B"}, {"C", "D"}], ["E"])
      layout = Layout.compute_layout(g)

      for nid <- g.node_order do
        assert Map.has_key?(layout.placements, nid), "Node #{nid} not placed"
      end
    end

    test "disconnected subgraphs are placed separately" do
      g = graph(:lr, [{"A", "B"}, {"C", "D"}])
      layout = Layout.compute_layout(g)
      pa = layout.placements["A"]
      pc = layout.placements["C"]
      assert pa.grid.row != pc.grid.row
    end
  end

  describe "draw coordinates" do
    test "all draw coordinates are non-negative" do
      g = graph(:lr, [{"A", "B"}, {"B", "C"}])
      layout = Layout.compute_layout(g)

      Enum.each(layout.placements, fn {_nid, p} ->
        assert p.draw_x >= 0
        assert p.draw_y >= 0
      end)
    end

    test "all nodes have positive width and height" do
      g =
        graph(:lr, [{"A", "B"}])
        |> Map.update!(:nodes, fn nodes ->
          Map.put(nodes, "A", Node.new("A", label: "Long Label Here"))
        end)

      layout = Layout.compute_layout(g)

      Enum.each(layout.placements, fn {_nid, p} ->
        assert p.draw_width >= 3
        assert p.draw_height >= 3
      end)
    end

    test "canvas size contains all nodes" do
      g = graph(:lr, [{"A", "B"}, {"B", "C"}])
      layout = Layout.compute_layout(g)
      assert layout.canvas_width > 0
      assert layout.canvas_height > 0

      Enum.each(layout.placements, fn {_nid, p} ->
        assert p.draw_x + p.draw_width <= layout.canvas_width + 1
        assert p.draw_y + p.draw_height <= layout.canvas_height + 1
      end)
    end
  end

  describe "large graph" do
    test "15-node tree layouts without errors" do
      g =
        graph(:td, [
          {"A", "B"},
          {"A", "C"},
          {"B", "D"},
          {"B", "E"},
          {"C", "F"},
          {"C", "G"},
          {"D", "H"},
          {"E", "H"},
          {"F", "I"},
          {"G", "I"},
          {"H", "J"},
          {"I", "J"},
          {"J", "K"},
          {"J", "L"},
          {"K", "M"},
          {"L", "M"}
        ])

      layout = Layout.compute_layout(g)
      assert map_size(layout.placements) == 13
      assert layout.canvas_width > 0
      assert layout.canvas_height > 0
    end
  end

  describe "stacked layout compaction" do
    test "stacked layout does not inflate gaps from wide layout" do
      edges =
        for i <- 0..7, do: {"N#{i}", "N#{i + 1}"}

      skip_edges =
        for i <- 0..5, do: {"N#{i}", "Target"}

      g = graph(:td, edges ++ skip_edges, ["Target"])

      wide = Layout.compute_layout(g)
      stacked = Layout.compute_layout(g, max_width: 40)

      lines_per_node = 8
      max_expected = map_size(stacked.placements) * lines_per_node
      assert stacked.canvas_height <= max_expected
      assert stacked.canvas_width <= 40 || stacked.canvas_width < wide.canvas_width
    end
  end
end
