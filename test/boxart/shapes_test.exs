defmodule Boxart.ShapesTest do
  use ExUnit.Case, async: true

  alias Boxart.Graph, as: BG
  alias Boxart.Graph.Edge

  defp render_shape(shape, label \\ nil) do
    label = label || Atom.to_string(shape)

    %BG{
      direction: :lr,
      nodes: %{
        "A" => %BG.Node{id: "A", label: label, shape: shape},
        "B" => %BG.Node{id: "B", label: "B"}
      },
      edges: [%Edge{source: "A", target: "B"}],
      node_order: ["A", "B"]
    }
    |> Boxart.Render.render_graph([])
  end

  describe "all shapes render with label visible" do
    @shapes [
      :rectangle,
      :rounded,
      :stadium,
      :subroutine,
      :diamond,
      :hexagon,
      :circle,
      :double_circle,
      :asymmetric,
      :cylinder,
      :trapezoid,
      :trapezoid_alt
    ]

    for shape <- @shapes do
      test "#{shape} renders" do
        output = render_shape(unquote(shape))
        assert String.contains?(output, Atom.to_string(unquote(shape)))
        assert String.length(String.trim(output)) > 0
      end
    end
  end

  describe "all shapes render in ASCII mode" do
    for shape <- [:rectangle, :rounded, :diamond, :hexagon, :stadium, :circle] do
      test "#{shape} ASCII" do
        label = Atom.to_string(unquote(shape))

        output =
          %BG{
            direction: :lr,
            nodes: %{
              "A" => %BG.Node{id: "A", label: label, shape: unquote(shape)},
              "B" => %BG.Node{id: "B", label: "B"}
            },
            edges: [%Edge{source: "A", target: "B"}],
            node_order: ["A", "B"]
          }
          |> Boxart.Render.render_graph(charset: :ascii)

        assert String.contains?(output, label)
      end
    end
  end

  describe "shape-specific characters" do
    test "rectangle has square corners" do
      output = render_shape(:rectangle, "Hello")
      assert String.contains?(output, "┌")
      assert String.contains?(output, "┐")
      assert String.contains?(output, "└")
      assert String.contains?(output, "┘")
    end

    test "rounded has round corners" do
      output = render_shape(:rounded, "Hello")
      assert String.contains?(output, "╭")
      assert String.contains?(output, "╯")
    end

    test "diamond has markers" do
      output = render_shape(:diamond, "Decision")
      assert String.contains?(output, "◇")
    end

    test "stadium has parentheses" do
      output = render_shape(:stadium, "Pill")
      assert String.contains?(output, "(")
      assert String.contains?(output, ")")
    end

    test "hexagon has slashes" do
      output = render_shape(:hexagon, "Hex")
      assert String.contains?(output, "/")
      assert String.contains?(output, "\\")
    end

    test "cylinder has rounded top" do
      output = render_shape(:cylinder, "DB")
      assert String.contains?(output, "╭")
      assert String.contains?(output, "╰")
    end
  end

  describe "all shapes in one graph" do
    test "renders without errors" do
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
        %Edge{source: "A", target: "B"},
        %Edge{source: "B", target: "C"},
        %Edge{source: "C", target: "D"},
        %Edge{source: "D", target: "E"},
        %Edge{source: "E", target: "F"}
      ]

      output =
        %BG{
          direction: :td,
          nodes: nodes,
          edges: edges,
          node_order: ~w(A B C D E F)
        }
        |> Boxart.Render.render_graph([])

      for label <- ~w(Rect Round Diam Stad Hex Circ) do
        assert String.contains?(output, label)
      end
    end
  end
end
