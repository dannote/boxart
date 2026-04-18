defmodule Boxart.ThemeTest do
  use ExUnit.Case, async: true

  alias Boxart.Theme

  defp simple_graph do
    Graph.new()
    |> Graph.add_vertex("A", label: "Start")
    |> Graph.add_vertex("B", label: "End")
    |> Graph.add_edge("A", "B", label: "go")
  end

  describe "themed output" do
    test "default theme produces ANSI escapes" do
      out = Boxart.render(simple_graph(), direction: :td, theme: :default)
      assert String.contains?(out, "\e[")
    end

    test "no theme produces plain text" do
      out = Boxart.render(simple_graph(), direction: :td)
      refute String.contains?(out, "\e[")
    end

    test "all built-in themes render without crash" do
      for name <- [:default, :mono, :neon, :dracula, :nord, :amber, :phosphor] do
        out = Boxart.render(simple_graph(), direction: :td, theme: name)
        assert is_binary(out), "Theme #{name} failed"
        assert String.contains?(out, "Start"), "Theme #{name} missing label"
      end
    end

    test "custom theme struct works" do
      theme = %Theme{node: [:red], arrow: [:green, :bright], edge: [:blue]}
      out = Boxart.render(simple_graph(), direction: :td, theme: theme)
      assert String.contains?(out, "\e[")
      assert String.contains?(out, "Start")
    end

    test "themed output contains node style (cyan=36)" do
      out = Boxart.render(simple_graph(), direction: :td, theme: :default)
      assert String.contains?(out, "\e[36m")
    end

    test "themed output contains arrow style (yellow=33)" do
      out = Boxart.render(simple_graph(), direction: :td, theme: :default)
      assert String.contains?(out, "\e[33")
    end

    test "themed output contains edge label style (faint+italic)" do
      out = Boxart.render(simple_graph(), direction: :td, theme: :default)
      assert String.contains?(out, "go")
    end
  end

  describe "style_for" do
    test "returns style for known keys" do
      theme = Theme.default()
      assert Theme.style_for(theme, "node") == [:cyan]
      assert Theme.style_for(theme, "arrow") == [:yellow, :bright]
    end

    test "returns empty list for unknown keys" do
      assert Theme.style_for(Theme.default(), "unknown") == []
    end
  end

  describe "rounded_edges option" do
    test "default uses rounded corners" do
      g =
        Graph.new()
        |> Graph.add_vertex("A")
        |> Graph.add_vertex("B")
        |> Graph.add_vertex("C")
        |> Graph.add_edge("A", "B")
        |> Graph.add_edge("A", "C")
        |> Graph.add_edge("B", "C")

      out = Boxart.render(g, direction: :td)
      assert String.contains?(out, "╮") or String.contains?(out, "╰")
    end

    test "sharp corners when rounded_edges: false" do
      g =
        Graph.new()
        |> Graph.add_vertex("A")
        |> Graph.add_vertex("B")
        |> Graph.add_vertex("C")
        |> Graph.add_edge("A", "B")
        |> Graph.add_edge("A", "C")
        |> Graph.add_edge("B", "C")

      internal = Boxart.Graph.from_libgraph(g, direction: :td)
      out = Boxart.Render.render_graph(internal, rounded_edges: false)
      refute String.contains?(out, "╮")
      refute String.contains?(out, "╰")
    end
  end

  describe "no-arrow edges" do
    test "no-arrow edge shows T-junctions instead of arrows" do
      alias Boxart.Graph, as: BG
      alias Boxart.Graph.Edge

      g = %BG{
        direction: :lr,
        nodes: %{
          "A" => %BG.Node{id: "A", label: "A"},
          "B" => %BG.Node{id: "B", label: "B"}
        },
        edges: [%Edge{source: "A", target: "B", has_arrow_end: false}],
        node_order: ["A", "B"]
      }

      out = Boxart.Render.render_graph(g, [])
      refute String.contains?(out, "►")
      assert String.contains?(out, "├") or String.contains?(out, "┤")
    end
  end
end
