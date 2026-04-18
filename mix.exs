defmodule Boxart.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/dannote/boxart"

  def project do
    [
      app: :boxart,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      dialyzer: [
        plt_file: {:no_warn, "_build/dev/dialyxir_plt.plt"}
      ],
      name: "Boxart",
      description: "Terminal graph rendering with Unicode box-drawing",
      source_url: @source_url,
      docs: docs(),
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def cli do
    [preferred_envs: [ci: :test]]
  end

  defp aliases do
    [
      ci: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict",
        "dialyzer",
        "test"
      ]
    ]
  end

  defp deps do
    [
      {:libgraph, "~> 0.16.0"},
      {:makeup, "~> 1.0", optional: true},
      {:makeup_elixir, "~> 1.0", optional: true},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      main: "Boxart",
      extras: ["README.md", "LICENSE"],
      source_url: @source_url,
      source_ref: "master",
      groups_for_modules: [
        "Public API": [Boxart, Boxart.Diagram, Boxart.Theme],
        "Graph Rendering": [
          Boxart.Render,
          Boxart.Render.Shapes,
          Boxart.CodeNode,
          Boxart.Highlight
        ],
        "Specialized Renderers": [
          Boxart.Render.StateDiagram,
          Boxart.Render.Sequence,
          Boxart.Render.GitGraph,
          Boxart.Render.Gantt,
          Boxart.Render.Mindmap,
          Boxart.Render.PieChart
        ],
        "Layout Engine": [
          Boxart.Layout,
          Boxart.Layout.Layers,
          Boxart.Layout.Placement,
          Boxart.Layout.Coordinates,
          Boxart.Layout.Subgraphs
        ],
        Routing: [Boxart.Routing, Boxart.Routing.Pathfinder],
        "Canvas & Charset": [Boxart.Canvas, Boxart.Charset],
        Internal: [Boxart.Graph, Boxart.Utils]
      ]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib mix.exs README.md LICENSE .formatter.exs)
    ]
  end
end
