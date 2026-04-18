defmodule Boxart.Charset do
  @moduledoc """
  Character sets for Unicode and ASCII box-drawing rendering.

  Each `Charset` struct holds all glyphs needed to draw nodes, edges,
  corners, arrows, and subgraph borders, organized into sub-structs.
  """

  defmodule Box do
    @moduledoc "Box-drawing border characters."

    @type t :: %__MODULE__{
            top_left: String.t(),
            top_right: String.t(),
            bottom_left: String.t(),
            bottom_right: String.t(),
            horizontal: String.t(),
            vertical: String.t(),
            round_top_left: String.t(),
            round_top_right: String.t(),
            round_bottom_left: String.t(),
            round_bottom_right: String.t()
          }

    defstruct [
      :top_left,
      :top_right,
      :bottom_left,
      :bottom_right,
      :horizontal,
      :vertical,
      :round_top_left,
      :round_top_right,
      :round_bottom_left,
      :round_bottom_right
    ]
  end

  defmodule Arrows do
    @moduledoc "Arrow head characters."

    @type t :: %__MODULE__{
            right: String.t(),
            left: String.t(),
            down: String.t(),
            up: String.t()
          }

    defstruct [:right, :left, :down, :up]
  end

  defmodule Lines do
    @moduledoc "Line characters (horizontal, vertical, dotted, thick)."

    @type t :: %__MODULE__{
            horizontal: String.t(),
            vertical: String.t(),
            dotted_h: String.t(),
            dotted_v: String.t(),
            thick_h: String.t(),
            thick_v: String.t()
          }

    defstruct [:horizontal, :vertical, :dotted_h, :dotted_v, :thick_h, :thick_v]
  end

  defmodule Junctions do
    @moduledoc "Junction and corner characters (tees, crosses)."

    @type t :: %__MODULE__{
            corner_top_left: String.t(),
            corner_top_right: String.t(),
            corner_bottom_left: String.t(),
            corner_bottom_right: String.t(),
            tee_right: String.t(),
            tee_left: String.t(),
            tee_down: String.t(),
            tee_up: String.t(),
            cross: String.t()
          }

    defstruct [
      :corner_top_left,
      :corner_top_right,
      :corner_bottom_left,
      :corner_bottom_right,
      :tee_right,
      :tee_left,
      :tee_down,
      :tee_up,
      :cross
    ]
  end

  defmodule Markers do
    @moduledoc "Special markers (diamonds, circles, crosses) for edge endpoints."

    @type t :: %__MODULE__{
            diamond_top: String.t(),
            diamond_bottom: String.t(),
            diamond_left: String.t(),
            diamond_right: String.t(),
            circle_endpoint: String.t(),
            cross_endpoint: String.t()
          }

    defstruct [
      :diamond_top,
      :diamond_bottom,
      :diamond_left,
      :diamond_right,
      :circle_endpoint,
      :cross_endpoint
    ]
  end

  defmodule Subgraph do
    @moduledoc "Subgraph border characters."

    @type t :: %__MODULE__{
            top_left: String.t(),
            top_right: String.t(),
            bottom_left: String.t(),
            bottom_right: String.t(),
            horizontal: String.t(),
            vertical: String.t()
          }

    defstruct [:top_left, :top_right, :bottom_left, :bottom_right, :horizontal, :vertical]
  end

  @type t :: %__MODULE__{
          box: Box.t(),
          arrows: Arrows.t(),
          lines: Lines.t(),
          junctions: Junctions.t(),
          markers: Markers.t(),
          subgraph: Subgraph.t()
        }

  defstruct [:box, :arrows, :lines, :junctions, :markers, :subgraph]

  @doc "Returns a charset using Unicode box-drawing characters."
  @spec unicode() :: t()
  def unicode do
    %__MODULE__{
      box: %Box{
        top_left: "┌",
        top_right: "┐",
        bottom_left: "└",
        bottom_right: "┘",
        horizontal: "─",
        vertical: "│",
        round_top_left: "╭",
        round_top_right: "╮",
        round_bottom_left: "╰",
        round_bottom_right: "╯"
      },
      arrows: %Arrows{
        right: "►",
        left: "◄",
        down: "▼",
        up: "▲"
      },
      lines: %Lines{
        horizontal: "─",
        vertical: "│",
        dotted_h: "┄",
        dotted_v: "┆",
        thick_h: "━",
        thick_v: "┃"
      },
      junctions: %Junctions{
        corner_top_left: "┌",
        corner_top_right: "┐",
        corner_bottom_left: "└",
        corner_bottom_right: "┘",
        tee_right: "├",
        tee_left: "┤",
        tee_down: "┬",
        tee_up: "┴",
        cross: "┼"
      },
      markers: %Markers{
        diamond_top: "◇",
        diamond_bottom: "◇",
        diamond_left: "◇",
        diamond_right: "◇",
        circle_endpoint: "○",
        cross_endpoint: "×"
      },
      subgraph: %Subgraph{
        top_left: "┌",
        top_right: "┐",
        bottom_left: "└",
        bottom_right: "┘",
        horizontal: "─",
        vertical: "│"
      }
    }
  end

  @doc "Selects a charset from keyword options."
  @spec from_opts(keyword()) :: t()
  def from_opts(opts) do
    case Keyword.get(opts, :charset, :unicode) do
      :ascii -> ascii()
      _ -> unicode()
    end
  end

  @doc "Returns a charset using plain ASCII characters."
  @spec ascii() :: t()
  def ascii do
    %__MODULE__{
      box: %Box{
        top_left: "+",
        top_right: "+",
        bottom_left: "+",
        bottom_right: "+",
        horizontal: "-",
        vertical: "|",
        round_top_left: "+",
        round_top_right: "+",
        round_bottom_left: "+",
        round_bottom_right: "+"
      },
      arrows: %Arrows{
        right: ">",
        left: "<",
        down: "v",
        up: "^"
      },
      lines: %Lines{
        horizontal: "-",
        vertical: "|",
        dotted_h: ".",
        dotted_v: ":",
        thick_h: "=",
        thick_v: "H"
      },
      junctions: %Junctions{
        corner_top_left: "+",
        corner_top_right: "+",
        corner_bottom_left: "+",
        corner_bottom_right: "+",
        tee_right: "+",
        tee_left: "+",
        tee_down: "+",
        tee_up: "+",
        cross: "+"
      },
      markers: %Markers{
        diamond_top: "/",
        diamond_bottom: "\\",
        diamond_left: "/",
        diamond_right: "\\",
        circle_endpoint: "o",
        cross_endpoint: "x"
      },
      subgraph: %Subgraph{
        top_left: "+",
        top_right: "+",
        bottom_left: "+",
        bottom_right: "+",
        horizontal: "-",
        vertical: "|"
      }
    }
  end
end
