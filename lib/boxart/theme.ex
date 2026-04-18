defmodule Boxart.Theme do
  @moduledoc """
  Color themes for terminal diagram output.

  Maps semantic style keys (`:node`, `:edge`, `:arrow`, etc.) to
  `IO.ANSI` format sequences. Use built-in themes or define your own.

  ## Built-in themes

    * `:default` — cyan nodes, yellow arrows, dim edges
    * `:mono` — white/gray, no color
    * `:neon` — magenta nodes, green arrows
    * `:dracula` — purple/green on dark background
    * `:nord` — cool blues and greens
    * `:amber` — warm amber/gold tones
    * `:phosphor` — green terminal aesthetic

  ## Custom themes

      my_theme = %Boxart.Theme{
        node: [:blue],
        edge: [:white],
        arrow: [:red, :bright],
        label: [:bright],
        edge_label: [:faint, :italic]
      }

      Boxart.render(graph, theme: my_theme)
  """

  require Logger

  @type ansi_style :: [atom()]

  @type t :: %__MODULE__{
          node: ansi_style(),
          edge: ansi_style(),
          arrow: ansi_style(),
          subgraph: ansi_style(),
          label: ansi_style(),
          edge_label: ansi_style(),
          subgraph_label: ansi_style(),
          dim: ansi_style()
        }

  defstruct node: [],
            edge: [],
            arrow: [],
            subgraph: [],
            label: [],
            edge_label: [],
            subgraph_label: [],
            dim: [:faint]

  @doc "Returns a built-in theme by name."
  @spec get(atom()) :: t()
  def get(:default), do: default()
  def get(:mono), do: mono()
  def get(:neon), do: neon()
  def get(:dracula), do: dracula()
  def get(:nord), do: nord()
  def get(:amber), do: amber()
  def get(:phosphor), do: phosphor()

  def get(name) do
    Logger.warning("Unknown Boxart theme: #{inspect(name)}, using :default")
    default()
  end

  @doc false
  def default do
    %__MODULE__{
      node: [:cyan],
      edge: [:faint],
      arrow: [:yellow, :bright],
      subgraph: [:faint, :cyan],
      label: [:bright],
      edge_label: [:faint, :italic],
      subgraph_label: [:cyan, :bright],
      dim: [:faint]
    }
  end

  @doc false
  def mono do
    %__MODULE__{
      node: [:bright],
      edge: [:faint],
      arrow: [:bright],
      subgraph: [:faint],
      label: [],
      edge_label: [:faint, :italic],
      subgraph_label: [:bright],
      dim: [:faint]
    }
  end

  @doc false
  def neon do
    %__MODULE__{
      node: [:magenta, :bright],
      edge: [:faint, :cyan],
      arrow: [:green, :bright],
      subgraph: [:faint, :magenta],
      label: [:bright],
      edge_label: [:cyan, :italic],
      subgraph_label: [:cyan, :bright],
      dim: [:faint]
    }
  end

  @doc false
  def dracula do
    %__MODULE__{
      node: [:light_magenta],
      edge: [:light_black],
      arrow: [:green, :bright],
      subgraph: [:magenta],
      label: [:bright],
      edge_label: [:light_cyan, :italic],
      subgraph_label: [:magenta, :bright],
      dim: [:faint]
    }
  end

  @doc false
  def nord do
    %__MODULE__{
      node: [:light_cyan],
      edge: [:faint],
      arrow: [:green],
      subgraph: [:light_blue],
      label: [:bright],
      edge_label: [:magenta, :italic],
      subgraph_label: [:light_blue, :bright],
      dim: [:faint]
    }
  end

  @doc false
  def amber do
    %__MODULE__{
      node: [:yellow, :bright],
      edge: [:yellow, :faint],
      arrow: [:yellow, :bright],
      subgraph: [:yellow],
      label: [:yellow, :bright],
      edge_label: [:yellow, :faint, :italic],
      subgraph_label: [:yellow, :bright],
      dim: [:faint]
    }
  end

  @doc false
  def phosphor do
    %__MODULE__{
      node: [:green, :bright],
      edge: [:green, :faint],
      arrow: [:green, :bright],
      subgraph: [:green],
      label: [:green, :bright],
      edge_label: [:green, :faint, :italic],
      subgraph_label: [:green, :bright],
      dim: [:faint]
    }
  end

  @doc """
  Returns the ANSI format sequence for a style key.
  """
  @spec style_for(t(), String.t()) :: ansi_style()
  def style_for(%__MODULE__{} = theme, key) do
    theme |> to_map() |> Map.get(key, [])
  end

  @doc "Converts the theme to a map of style key => ANSI atoms. Useful for precomputing."
  @spec to_map(t()) :: %{String.t() => ansi_style()}
  def to_map(%__MODULE__{} = theme) do
    %{
      "node" => theme.node,
      "edge" => theme.edge,
      "arrow" => theme.arrow,
      "subgraph" => theme.subgraph,
      "label" => theme.label,
      "edge_label" => theme.edge_label,
      "subgraph_label" => theme.subgraph_label,
      "dim" => theme.dim
    }
  end
end
