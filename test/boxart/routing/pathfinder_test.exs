defmodule Boxart.Routing.PathfinderTest do
  use ExUnit.Case, async: true

  alias Boxart.Routing.Pathfinder

  describe "heuristic/4" do
    test "axis-aligned distance" do
      assert Pathfinder.heuristic(0, 0, 5, 0) == 5.0
      assert Pathfinder.heuristic(0, 0, 0, 3) == 3.0
    end

    test "non-aligned adds corner penalty" do
      assert Pathfinder.heuristic(0, 0, 3, 4) == 8.0
    end

    test "same point is zero" do
      assert Pathfinder.heuristic(2, 3, 2, 3) == 0.0
    end
  end

  describe "find_path/5" do
    test "same start and end" do
      assert Pathfinder.find_path(1, 1, 1, 1, fn _, _ -> true end) == [{1, 1}]
    end

    test "straight horizontal path" do
      path = Pathfinder.find_path(0, 0, 3, 0, fn _, _ -> true end)
      assert hd(path) == {0, 0}
      assert List.last(path) == {3, 0}
      assert length(path) == 4
    end

    test "straight vertical path" do
      path = Pathfinder.find_path(0, 0, 0, 3, fn _, _ -> true end)
      assert hd(path) == {0, 0}
      assert List.last(path) == {0, 3}
      assert length(path) == 4
    end

    test "path around obstacle" do
      obstacle = MapSet.new([{1, 0}, {1, 1}])
      is_free = fn c, r -> not MapSet.member?(obstacle, {c, r}) end
      path = Pathfinder.find_path(0, 0, 2, 0, is_free)
      assert path != nil
      assert hd(path) == {0, 0}
      assert List.last(path) == {2, 0}
      refute Enum.any?(path, fn p -> MapSet.member?(obstacle, p) end)
    end

    test "no path returns nil" do
      is_free = fn c, r -> c == 0 and r == 0 end
      assert Pathfinder.find_path(0, 0, 5, 0, is_free) == nil
    end

    test "soft obstacles are traversable at higher cost" do
      soft = MapSet.new([{1, 0}])
      path = Pathfinder.find_path(0, 0, 2, 0, fn _, _ -> true end, soft_obstacles: soft)
      assert path != nil
      assert hd(path) == {0, 0}
      assert List.last(path) == {2, 0}
    end

    test "max_iterations stops search" do
      assert Pathfinder.find_path(0, 0, 100, 100, fn _, _ -> true end, max_iterations: 5) == nil
    end
  end

  describe "simplify_path/1" do
    test "short paths unchanged" do
      assert Pathfinder.simplify_path([{0, 0}]) == [{0, 0}]
      assert Pathfinder.simplify_path([{0, 0}, {1, 0}]) == [{0, 0}, {1, 0}]
    end

    test "removes collinear points" do
      path = [{0, 0}, {1, 0}, {2, 0}, {3, 0}]
      assert Pathfinder.simplify_path(path) == [{0, 0}, {3, 0}]
    end

    test "keeps corners" do
      path = [{0, 0}, {1, 0}, {1, 1}, {1, 2}]
      assert Pathfinder.simplify_path(path) == [{0, 0}, {1, 0}, {1, 2}]
    end

    test "L-shaped path preserved" do
      path = [{0, 0}, {1, 0}, {2, 0}, {2, 1}, {2, 2}]
      assert Pathfinder.simplify_path(path) == [{0, 0}, {2, 0}, {2, 2}]
    end
  end
end
