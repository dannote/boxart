defmodule Boxart.Render.StateDiagramTest do
  use ExUnit.Case, async: true

  alias Boxart.Render.StateDiagram, as: SDRenderer
  alias SDRenderer.{State, StateDiagram, Transition}

  defp diagram(states, transitions) do
    %StateDiagram{states: states, transitions: transitions}
  end

  describe "basic rendering" do
    test "simple two-state diagram" do
      d =
        diagram(
          [%State{id: "Idle"}, %State{id: "Running"}],
          [%Transition{from: "Idle", to: "Running", label: "start"}]
        )

      out = SDRenderer.render(d)
      assert String.contains?(out, "Idle")
      assert String.contains?(out, "Running")
      assert String.contains?(out, "start")
    end

    test "start and end states" do
      d =
        diagram(
          [
            %State{id: "s", type: :start},
            %State{id: "Active"},
            %State{id: "e", type: :end}
          ],
          [
            %Transition{from: "s", to: "Active"},
            %Transition{from: "Active", to: "e"}
          ]
        )

      out = SDRenderer.render(d)
      assert String.contains?(out, "●")
      assert String.contains?(out, "◉")
      assert String.contains?(out, "Active")
    end

    test "three states with cycle" do
      d =
        diagram(
          [%State{id: "A"}, %State{id: "B"}, %State{id: "C"}],
          [
            %Transition{from: "A", to: "B", label: "go"},
            %Transition{from: "B", to: "C", label: "next"},
            %Transition{from: "C", to: "A", label: "retry"}
          ]
        )

      out = SDRenderer.render(d)

      for s <- ~w(A B C) do
        assert String.contains?(out, s)
      end

      lines = String.split(out, "\n")
      assert length(lines) < 40
    end

    test "states use rounded boxes" do
      d =
        diagram(
          [%State{id: "X"}],
          []
        )

      out = SDRenderer.render(d)
      assert String.contains?(out, "╭") or String.contains?(out, "╰")
    end

    test "custom labels" do
      d =
        diagram(
          [%State{id: "s1", label: "Waiting for input"}],
          []
        )

      out = SDRenderer.render(d)
      assert String.contains?(out, "Waiting for input")
    end

    test "LR direction" do
      d =
        diagram(
          [%State{id: "A"}, %State{id: "B"}],
          [%Transition{from: "A", to: "B"}]
        )

      out = SDRenderer.render(d, direction: :lr)
      lines = String.split(out, "\n")
      a_row = Enum.find_index(lines, &String.contains?(&1, "A"))
      b_row = Enum.find_index(lines, &String.contains?(&1, "B"))
      assert a_row == b_row
    end
  end
end
