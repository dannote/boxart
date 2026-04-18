defmodule Boxart.Render.StateDiagram do
  @moduledoc """
  Renderer for state diagrams.

  State diagrams show states as rounded boxes with transitions
  between them. Special `[*]` markers represent start and end states.

  ## Example

      alias Boxart.Render.StateDiagram
      alias StateDiagram.{State, Transition, StateDiagram}

      diagram = %StateDiagram{
        states: [
          %State{id: "start", type: :start},
          %State{id: "Idle"},
          %State{id: "Processing"},
          %State{id: "Done"},
          %State{id: "end", type: :end}
        ],
        transitions: [
          %Transition{from: "start", to: "Idle"},
          %Transition{from: "Idle", to: "Processing", label: "begin"},
          %Transition{from: "Processing", to: "Done", label: "complete"},
          %Transition{from: "Done", to: "end"}
        ]
      }

      StateDiagram.render(diagram) |> IO.puts()
  """

  @behaviour Boxart.Diagram

  defmodule State do
    @moduledoc "A state in the diagram."

    @type state_type :: :normal | :start | :end

    @type t :: %__MODULE__{
            id: String.t(),
            label: String.t() | nil,
            type: state_type()
          }

    @enforce_keys [:id]
    defstruct [:id, :label, type: :normal]
  end

  defmodule Transition do
    @moduledoc "A transition between states."

    @type t :: %__MODULE__{
            from: String.t(),
            to: String.t(),
            label: String.t()
          }

    @enforce_keys [:from, :to]
    defstruct [:from, :to, label: ""]
  end

  defmodule StateDiagram do
    @moduledoc "A state diagram with states and transitions."

    @type t :: %__MODULE__{
            states: [Boxart.Render.StateDiagram.State.t()],
            transitions: [Boxart.Render.StateDiagram.Transition.t()]
          }

    defstruct states: [], transitions: []
  end

  @doc """
  Renders a state diagram as a string.

  ## Options

    * `:charset` — `:unicode` (default) or `:ascii`
    * `:direction` — `:td` (default) or `:lr`
  """
  @spec render(StateDiagram.t(), keyword()) :: String.t()
  @impl true
  def render(%StateDiagram{} = diagram, opts \\ []) do
    direction = Keyword.get(opts, :direction, :td)

    graph =
      Graph.new()
      |> add_states(diagram.states)
      |> add_transitions(diagram.transitions)

    Boxart.render(graph, Keyword.merge(opts, direction: direction))
  end

  defp add_states(graph, states) do
    Enum.reduce(states, graph, fn state, g ->
      labels = build_state_labels(state)
      Graph.add_vertex(g, state.id, labels)
    end)
  end

  defp build_state_labels(%State{type: :start}), do: [label: "●", shape: :start_state]
  defp build_state_labels(%State{type: :end}), do: [label: "◉", shape: :end_state]

  defp build_state_labels(%State{label: nil, id: id}),
    do: [label: id, shape: :rounded]

  defp build_state_labels(%State{label: label}),
    do: [label: label, shape: :rounded]

  defp add_transitions(graph, transitions) do
    Enum.reduce(transitions, graph, fn t, g ->
      Graph.add_edge(g, t.from, t.to, label: t.label)
    end)
  end
end
