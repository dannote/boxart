defmodule Boxart.RoutingTest do
  use ExUnit.Case, async: true

  alias Boxart.Graph
  alias Boxart.Graph.{Node, Edge}
  alias Boxart.Layout
  alias Boxart.Routing
  alias Boxart.Routing.Pathfinder

  defp graph(direction, edges) do
    node_ids = edges |> Enum.flat_map(fn {s, t} -> [s, t] end) |> Enum.uniq()
    nodes = Map.new(node_ids, fn id -> {id, Node.new(id)} end)
    edge_structs = Enum.map(edges, fn {s, t} -> %Edge{source: s, target: t} end)

    %Graph{
      direction: direction,
      nodes: nodes,
      edges: edge_structs,
      node_order: node_ids
    }
  end

  describe "heuristic" do
    test "same point" do
      assert Pathfinder.heuristic(0, 0, 0, 0) == 0.0
    end

    test "horizontal" do
      assert Pathfinder.heuristic(0, 0, 5, 0) == 5.0
    end

    test "vertical" do
      assert Pathfinder.heuristic(0, 0, 0, 5) == 5.0
    end

    test "diagonal has corner penalty" do
      assert Pathfinder.heuristic(0, 0, 5, 5) == 11.0
    end
  end

  describe "pathfinder" do
    test "straight path" do
      path = Pathfinder.find_path(0, 0, 5, 0, fn _c, _r -> true end)
      assert path != nil
      assert hd(path) == {0, 0}
      assert List.last(path) == {5, 0}
    end

    test "path around obstacle" do
      is_free = fn c, r -> not (c == 2 and r == 0) end
      path = Pathfinder.find_path(0, 0, 4, 0, is_free)
      assert path != nil
      refute {2, 0} in path
      assert hd(path) == {0, 0}
      assert List.last(path) == {4, 0}
    end

    test "no path returns nil" do
      is_free = fn c, r -> c == 0 and r == 0 end
      assert Pathfinder.find_path(0, 0, 5, 5, is_free) == nil
    end

    test "adjacent cells" do
      path = Pathfinder.find_path(0, 0, 1, 0, fn _c, _r -> true end)
      assert path == [{0, 0}, {1, 0}]
    end
  end

  describe "simplify_path" do
    test "already simple" do
      assert Pathfinder.simplify_path([{0, 0}, {5, 0}]) == [{0, 0}, {5, 0}]
    end

    test "straight line" do
      path = [{0, 0}, {1, 0}, {2, 0}, {3, 0}]
      assert Pathfinder.simplify_path(path) == [{0, 0}, {3, 0}]
    end

    test "one corner" do
      path = [{0, 0}, {1, 0}, {2, 0}, {2, 1}, {2, 2}]
      assert Pathfinder.simplify_path(path) == [{0, 0}, {2, 0}, {2, 2}]
    end

    test "two corners" do
      path = [{0, 0}, {1, 0}, {2, 0}, {2, 1}, {2, 2}, {3, 2}, {4, 2}]
      assert Pathfinder.simplify_path(path) == [{0, 0}, {2, 0}, {2, 2}, {4, 2}]
    end
  end

  describe "edge routing" do
    test "simple LR routing" do
      g = graph(:lr, [{"A", "B"}])
      layout = Layout.compute_layout(g)
      routed = Routing.route_edges(g, layout)
      assert length(routed) == 1
      re = hd(routed)
      assert re.edge.source == "A"
      assert re.edge.target == "B"
      assert length(re.draw_path) >= 2
    end

    test "all edges are routed" do
      g = graph(:lr, [{"A", "B"}, {"A", "C"}, {"B", "D"}])
      layout = Layout.compute_layout(g)
      routed = Routing.route_edges(g, layout)
      assert length(routed) == 3
    end

    test "self-reference routing" do
      g = graph(:lr, [{"A", "A"}])
      layout = Layout.compute_layout(g)
      routed = Routing.route_edges(g, layout)
      assert length(routed) == 1
      re = hd(routed)
      assert length(re.draw_path) >= 3
    end

    test "edges don't route through unrelated node interiors" do
      g = graph(:lr, [{"A", "B"}, {"A", "C"}, {"B", "D"}, {"C", "D"}])
      layout = Layout.compute_layout(g)
      routed = Routing.route_edges(g, layout)

      node_cells =
        for {nid, p} <- layout.placements,
            dc <- -1..1,
            dr <- -1..1,
            into: %{} do
          {{p.grid.col + dc, p.grid.row + dr}, nid}
        end

      for re <- routed do
        re.grid_path
        |> Enum.slice(1..-2//1)
        |> Enum.each(fn {col, row} ->
          case Map.get(node_cells, {col, row}) do
            nil ->
              :ok

            owner ->
              assert owner in [re.edge.source, re.edge.target],
                     "Edge #{re.edge.source}->#{re.edge.target} routes through #{owner}"
          end
        end)
      end
    end

    test "draw path coordinates are non-negative" do
      g = graph(:lr, [{"A", "B"}, {"B", "C"}])
      layout = Layout.compute_layout(g)
      routed = Routing.route_edges(g, layout)

      for re <- routed, {x, y} <- re.draw_path do
        assert x >= 0, "Negative x in path: #{x}"
        assert y >= 0, "Negative y in path: #{y}"
      end
    end
  end
end
