defmodule Boxart.Render.Gantt do
  @moduledoc """
  Renderer for Gantt chart diagrams.

  Renders horizontal bar charts with tasks along the y-axis and time
  along the x-axis. Tasks are grouped by sections.

  ## Example

      alias Boxart.Render.Gantt
      alias Gantt.{Task, Section, Gantt}

      diagram = %Gantt{
        title: "Project Plan",
        sections: [
          %Section{
            title: "Phase 1",
            tasks: [
              %Task{title: "Design", start: ~D[2024-01-01], end: ~D[2024-01-15]},
              %Task{title: "Build", start: ~D[2024-01-10], end: ~D[2024-02-01], is_active: true}
            ]
          }
        ]
      }

      Gantt.render(diagram) |> IO.puts()
  """

  @behaviour Boxart.Diagram

  alias Boxart.Canvas
  alias Boxart.Utils

  @default_width 80

  defmodule Task do
    @moduledoc "A task in the Gantt chart."

    @type t :: %__MODULE__{
            id: String.t(),
            title: String.t(),
            start: Date.t() | nil,
            end: Date.t() | nil,
            is_done: boolean(),
            is_active: boolean(),
            is_crit: boolean(),
            is_milestone: boolean()
          }

    defstruct id: "",
              title: "",
              start: nil,
              end: nil,
              is_done: false,
              is_active: false,
              is_crit: false,
              is_milestone: false
  end

  defmodule Section do
    @moduledoc "A section grouping tasks."

    @type t :: %__MODULE__{
            title: String.t(),
            tasks: [Boxart.Render.Gantt.Task.t()]
          }

    @enforce_keys [:title]
    defstruct [:title, tasks: []]
  end

  defmodule Gantt do
    @moduledoc "A Gantt chart with sections and tasks."

    @type t :: %__MODULE__{
            title: String.t(),
            sections: [Boxart.Render.Gantt.Section.t()],
            today_marker: boolean()
          }

    defstruct title: "", sections: [], today_marker: false
  end

  @doc """
  Renders a Gantt chart as a string.

  ## Options

    * `:charset` — `:unicode` (default) or `:ascii`
    * `:width` — chart width in characters (default: `80`)
  """
  @spec render(Gantt.t(), keyword()) :: String.t()
  @impl true
  def render(diagram, opts \\ [])
  def render(%Gantt{sections: []}, _opts), do: ""

  def render(%Gantt{} = diagram, opts) do
    use_ascii = Keyword.get(opts, :charset) == :ascii
    width = Keyword.get(opts, :width, @default_width)
    chars = bar_chars(use_ascii)

    {tasks_flat, min_date, max_date, max_label_w} = collect_tasks(diagram)

    case {min_date, max_date} do
      {nil, _} -> ""
      {_, nil} -> ""
      {mn, mx} -> do_render(diagram, tasks_flat, mn, mx, max_label_w, width, chars, use_ascii)
    end
  end

  defp do_render(diagram, tasks_flat, min_date, max_date, max_label_w, width, chars, use_ascii) do
    total_days = max(Date.diff(max_date, min_date), 1)
    margin_l = max_label_w + 5
    chart_w = max(width - margin_l - 1, 10)

    title_rows = if diagram.title != "", do: 2, else: 0
    task_rows = length(tasks_flat)
    total_h = title_rows + task_rows + 3
    total_w = margin_l + chart_w + 1

    canvas = Canvas.new(total_w + 1, total_h + 1)
    canvas = draw_title(canvas, diagram.title, margin_l, chart_w)

    chart_ctx = %{
      margin_l: margin_l,
      chart_w: chart_w,
      total_days: total_days,
      min_date: min_date,
      chars: chars
    }

    canvas
    |> draw_tasks(tasks_flat, title_rows, chart_ctx)
    |> draw_axis(
      title_rows,
      title_rows + task_rows,
      margin_l,
      chart_w,
      total_days,
      min_date,
      use_ascii
    )
    |> Canvas.render()
  end

  defp bar_chars(true), do: %{normal: "#", active: "=", done: ".", crit: "!", milestone: "*"}
  defp bar_chars(false), do: %{normal: "█", active: "▓", done: "░", crit: "█", milestone: "◆"}

  defp collect_tasks(diagram) do
    {flat, min_d, max_d, max_w} =
      Enum.reduce(diagram.sections, {[], nil, nil, 0}, fn section, {acc, mn, mx, mw} ->
        mw = max(mw, Utils.display_width(section.title) + 2)
        header = {:section, section.title}

        {task_items, mn, mx, mw} =
          Enum.reduce(section.tasks, {[], mn, mx, mw}, fn task, {items, mn2, mx2, mw2} ->
            mw2 = max(mw2, Utils.display_width(task.title))
            mn2 = min_date(mn2, task.start)
            mx2 = max_date(mx2, task.end)
            {items ++ [{:task, task, task_style(task)}], mn2, mx2, mw2}
          end)

        {acc ++ [header | task_items], mn, mx, mw}
      end)

    {flat, min_d, max_d, max_w}
  end

  defp task_style(%Task{is_milestone: true}), do: :milestone
  defp task_style(%Task{is_done: true}), do: :done
  defp task_style(%Task{is_active: true}), do: :active
  defp task_style(%Task{is_crit: true}), do: :crit
  defp task_style(_), do: :normal

  defp min_date(nil, d), do: d
  defp min_date(d, nil), do: d
  defp min_date(a, b), do: if(Date.compare(a, b) == :lt, do: a, else: b)

  defp max_date(nil, d), do: d
  defp max_date(d, nil), do: d
  defp max_date(a, b), do: if(Date.compare(a, b) == :gt, do: a, else: b)

  defp draw_title(canvas, "", _margin_l, _chart_w), do: canvas

  defp draw_title(canvas, title, margin_l, chart_w) do
    tx = margin_l + div(chart_w - Utils.display_width(title), 2)
    Canvas.put_text(canvas, max(0, tx), 0, title, style: "label")
  end

  defp draw_tasks(canvas, tasks, start_row, chart_ctx) do
    {canvas, _row} =
      Enum.reduce(tasks, {canvas, start_row}, fn item, {acc, row} ->
        case item do
          {:section, title} ->
            {Canvas.put_text(acc, 1, row, title, style: "subgraph_label"), row + 1}

          {:task, task, style} ->
            {draw_task_bar(acc, task, style, row, chart_ctx), row + 1}
        end
      end)

    canvas
  end

  defp draw_task_bar(canvas, task, style, row, ctx) do
    %{
      margin_l: margin_l,
      chart_w: chart_w,
      total_days: total_days,
      min_date: min_date,
      chars: chars
    } = ctx

    avail = margin_l - 4
    label = truncate_label(task.title, avail)
    canvas = Canvas.put_text(canvas, 3, row, label, style: "edge_label")

    case {task.start, task.end} do
      {%Date{} = s, %Date{} = e} ->
        bar_start = margin_l + 1 + round(Date.diff(s, min_date) / total_days * (chart_w - 1))

        bar_end =
          max(
            margin_l + 1 + round(Date.diff(e, min_date) / total_days * (chart_w - 1)),
            bar_start + 1
          )

        ch = Map.get(chars, style, chars.normal)
        draw_bar(canvas, row, bar_start, bar_end, ch, style, chars)

      _ ->
        canvas
    end
  end

  defp draw_bar(canvas, row, bar_start, bar_end, _ch, :milestone, chars) do
    mid = div(bar_start + bar_end, 2)
    Canvas.put(canvas, mid, row, chars.milestone, merge: false, style: "arrow")
  end

  defp draw_bar(canvas, row, bar_start, bar_end, ch, _style, _chars) do
    Enum.reduce(bar_start..bar_end//1, canvas, fn c, acc ->
      Canvas.put(acc, c, row, ch, merge: false, style: "node")
    end)
  end

  defp draw_axis(canvas, title_rows, axis_row, margin_l, chart_w, total_days, min_date, use_ascii) do
    hz = if use_ascii, do: "-", else: "─"
    corner = if use_ascii, do: "+", else: "└"
    tick = if use_ascii, do: "+", else: "┬"
    vt = if use_ascii, do: "|", else: "│"

    canvas = Canvas.put(canvas, margin_l, axis_row, corner, merge: false, style: "edge")

    canvas =
      Enum.reduce((margin_l + 1)..(margin_l + chart_w - 1)//1, canvas, fn c, acc ->
        Canvas.put(acc, c, axis_row, hz, merge: false, style: "edge")
      end)

    canvas = draw_y_axis(canvas, margin_l, title_rows, axis_row, vt)
    draw_date_ticks(canvas, axis_row, margin_l, chart_w, total_days, min_date, tick)
  end

  defp draw_y_axis(canvas, col, start_row, end_row, vt) do
    Enum.reduce(start_row..(end_row - 1)//1, canvas, fn r, acc ->
      Canvas.put(acc, col, r, vt, merge: false, style: "edge")
    end)
  end

  defp draw_date_ticks(canvas, axis_row, margin_l, chart_w, total_days, min_date, tick) do
    n_ticks = min(6, max(total_days, 2))

    Enum.reduce(0..n_ticks, canvas, fn i, acc ->
      d = Date.add(min_date, round(i / n_ticks * total_days))
      label = Calendar.strftime(d, "%b %d")
      col = margin_l + 1 + round(i / n_ticks * (chart_w - 2))

      acc = Canvas.put(acc, col, axis_row, tick, merge: false, style: "edge")
      label_x = col - div(Utils.display_width(label), 2)
      Canvas.put_text(acc, max(0, label_x), axis_row + 1, label, style: "edge_label")
    end)
  end

  defp truncate_label(text, max_w) do
    if Utils.display_width(text) <= max_w, do: text, else: String.slice(text, 0, max_w - 1) <> "."
  end
end
