defmodule BoxartTest do
  use ExUnit.Case

  alias Boxart.Graph
  alias Boxart.Graph.{Edge, Node}

  test "render returns empty string for empty graph" do
    graph = %Graph{}
    assert Boxart.render(graph) == ""
  end

  test "render returns a string for a simple graph" do
    graph = %Graph{
      direction: :tb,
      nodes: %{
        "A" => %Node{id: "A", label: "Hello"},
        "B" => %Node{id: "B", label: "World"}
      },
      edges: [%Edge{source: "A", target: "B"}],
      node_order: ["A", "B"]
    }

    result = Boxart.render(graph)
    assert is_binary(result)
    assert String.contains?(result, "Hello")
    assert String.contains?(result, "World")
  end

  test "render supports ascii charset" do
    graph = %Graph{
      direction: :tb,
      nodes: %{"A" => %Node{id: "A", label: "Test"}},
      edges: [],
      node_order: ["A"]
    }

    result = Boxart.render(graph, charset: :ascii)
    assert is_binary(result)
    assert String.contains?(result, "Test")
    refute String.contains?(result, "┌")
  end
end
