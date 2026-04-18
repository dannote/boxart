defmodule Boxart.Diagram do
  @moduledoc """
  Behaviour for specialized diagram renderers.

  Each renderer implements `render/2` which takes a diagram-specific
  struct and render options, returning a string.

  ## Built-in renderers

    * `Boxart.Render.Sequence` — sequence diagrams
    * `Boxart.Render.Mindmap` — mind maps
    * `Boxart.Render.PieChart` — horizontal bar charts
    * `Boxart.Render.StateDiagram` — state machine diagrams
    * `Boxart.Render.GitGraph` — git branch/commit graphs
    * `Boxart.Render.Gantt` — Gantt charts

  ## Implementing a custom renderer

      defmodule MyDiagram do
        @behaviour Boxart.Diagram

        defmodule Model do
          defstruct [:data]
        end

        @impl true
        def render(%Model{} = diagram, opts) do
          # return a string
        end
      end
  """

  @type opts :: keyword()

  @doc "Renders the diagram as a string."
  @callback render(diagram :: term(), opts()) :: String.t()
end
