defmodule Boxart.Render.Sequence do
  @moduledoc """
  Renderer for sequence diagrams.

  Draws participants as boxes at the top, vertical lifelines,
  horizontal message arrows between them, activation boxes,
  interaction blocks (loop/alt/opt/par), and notes.

  Uses `Boxart.Canvas` for all drawing operations.
  """

  alias Boxart.Canvas
  alias Boxart.Charset
  alias Boxart.Render.Shapes
  alias Boxart.Utils

  @type participant_type :: :participant | :actor
  @type line_type :: :solid | :dotted
  @type arrow_type :: :arrow | :open | :cross | :async

  defmodule Participant do
    @moduledoc false
    @type t :: %__MODULE__{id: String.t(), label: String.t(), type: :participant | :actor}
    defstruct [:id, :label, type: :participant]
  end

  defmodule Message do
    @moduledoc false

    @type t :: %__MODULE__{
            from: String.t(),
            to: String.t(),
            text: String.t(),
            line_type: :solid | :dotted,
            arrow_type: :arrow | :open | :cross | :async
          }
    defstruct [:from, :to, text: "", line_type: :solid, arrow_type: :arrow]
  end

  defmodule Note do
    @moduledoc false
    @type t :: %__MODULE__{
            text: String.t(),
            position: :right_of | :left_of | :over,
            participants: [String.t()]
          }
    defstruct [:text, :position, participants: []]
  end

  defmodule BlockSection do
    @moduledoc false
    @type t :: %__MODULE__{label: String.t(), events: [any()]}
    defstruct label: "", events: []
  end

  defmodule Block do
    @moduledoc false
    @type t :: %__MODULE__{
            kind: String.t(),
            label: String.t(),
            events: [any()],
            sections: [BlockSection.t()]
          }
    defstruct [:kind, label: "", events: [], sections: []]
  end

  defmodule Activate do
    @moduledoc false
    @type t :: %__MODULE__{participant: String.t(), active: boolean()}
    defstruct [:participant, :active]
  end

  defmodule Destroy do
    @moduledoc false
    @type t :: %__MODULE__{participant: String.t()}
    defstruct [:participant]
  end

  @type event :: Message.t() | Note.t() | Block.t() | Activate.t() | Destroy.t()

  defmodule SequenceDiagram do
    @moduledoc false
    @type t :: %__MODULE__{
            participants: [Boxart.Render.Sequence.Participant.t()],
            events: [Boxart.Render.Sequence.event()],
            autonumber: boolean()
          }
    defstruct participants: [], events: [], autonumber: false
  end

  @box_pad 4
  @box_height 3
  @actor_height 5
  @min_gap 16
  @event_row_h 2
  @block_start_h 3
  @block_section_h 2
  @block_end_h 2
  @top_margin 0
  @bottom_margin 1

  defmodule BlockStart do
    @moduledoc false
    defstruct [:block, :depth]
  end

  defmodule BlockSectionBreak do
    @moduledoc false
    defstruct [:section, :depth]
  end

  defmodule BlockEnd do
    @moduledoc false
    defstruct [:block, :depth]
  end

  defmodule Layout do
    @moduledoc false
    defstruct [:col_centers, :box_widths, :width, :height, :header_height, :row_offsets]
  end

  @doc """
  Renders a `SequenceDiagram` to a string.

  ## Options

    * `:charset` — `:unicode` (default) or `:ascii`
    * `:padding_x` — horizontal padding inside participant boxes (default: `#{@box_pad}`)
    * `:gap` — minimum gap between participant centers (default: `#{@min_gap}`)
  """
  @spec render(SequenceDiagram.t(), keyword()) :: String.t()
  def render(%SequenceDiagram{} = diagram, opts \\ []) do
    diagram
    |> render_canvas(opts)
    |> Canvas.to_string()
  end

  @doc """
  Renders a `SequenceDiagram` to a `Boxart.Canvas`.
  """
  @spec render_canvas(SequenceDiagram.t(), keyword()) :: Canvas.t()
  def render_canvas(%SequenceDiagram{} = diagram, opts \\ []) do
    cs = charset_from_opts(opts)
    use_ascii = Keyword.get(opts, :charset) == :ascii
    padding_x = Keyword.get(opts, :padding_x, @box_pad)
    gap = Keyword.get(opts, :gap, @min_gap)
    flat = flatten_events(diagram.events)
    layout = compute_layout(diagram, flat, padding_x, gap)
    do_render(diagram, flat, layout, cs, use_ascii)
  end

  defp do_render(_diagram, _flat, %Layout{width: 0}, _cs, _use_ascii), do: Canvas.new(1, 1)

  defp do_render(diagram, flat, layout, cs, use_ascii) do
    activation_ranges = compute_activation_ranges(flat, layout.row_offsets)
    destroyed = compute_destroyed(flat, layout.row_offsets)

    Canvas.new(layout.width, layout.height)
    |> draw_participant_headers(diagram, layout, cs, use_ascii)
    |> draw_lifelines(diagram, layout, activation_ranges, destroyed, use_ascii)
    |> draw_block_side_borders(flat, layout, cs)
    |> draw_events(diagram, flat, layout, cs, use_ascii)
  end

  # Layout

  defp compute_layout(%SequenceDiagram{participants: []}, _flat, _pad, _gap) do
    %Layout{
      col_centers: [],
      box_widths: [],
      width: 0,
      height: 0,
      header_height: 0,
      row_offsets: []
    }
  end

  defp compute_layout(diagram, flat, padding_x, min_gap) do
    n = length(diagram.participants)
    box_widths = Enum.map(diagram.participants, &participant_box_width(&1, padding_x))
    header_height = diagram.participants |> Enum.map(&kind_height(&1.type)) |> Enum.max()
    {event_heights, effective_labels} = compute_event_metrics(flat, diagram.autonumber)
    gap_mins = compute_gap_mins(diagram, flat, effective_labels, n, min_gap)
    col_centers = build_col_centers(box_widths, gap_mins, n)
    max_right = compute_max_right(col_centers, box_widths, flat, diagram)
    row_offsets = build_row_offsets(event_heights, @top_margin + header_height + 1)

    %Layout{
      col_centers: col_centers,
      box_widths: box_widths,
      width: max_right,
      height: @top_margin + header_height + 1 + Enum.sum(event_heights) + @bottom_margin,
      header_height: header_height,
      row_offsets: row_offsets
    }
  end

  defp participant_box_width(p, padding_x), do: max(Utils.display_width(p.label) + padding_x, 12)

  defp kind_height(:actor), do: @actor_height
  defp kind_height(_), do: @box_height

  defp compute_event_metrics(flat, autonumber) do
    {heights, labels, _} = Enum.reduce(flat, {[], [], 0}, &event_metric(&1, &2, autonumber))
    {Enum.reverse(heights), Enum.reverse(labels)}
  end

  defp event_metric(%Activate{}, {hs, ls, c}, _auto), do: {[0 | hs], ["" | ls], c}
  defp event_metric(%Destroy{}, {hs, ls, c}, _auto), do: {[@event_row_h | hs], ["" | ls], c}
  defp event_metric(%BlockStart{}, {hs, ls, c}, _auto), do: {[@block_start_h | hs], ["" | ls], c}

  defp event_metric(%BlockSectionBreak{}, {hs, ls, c}, _auto),
    do: {[@block_section_h | hs], ["" | ls], c}

  defp event_metric(%BlockEnd{}, {hs, ls, c}, _auto), do: {[@block_end_h | hs], ["" | ls], c}

  defp event_metric(%Note{text: text}, {hs, ls, c}, _auto) do
    h = length(note_lines(text)) + 3
    {[h | hs], ["" | ls], c}
  end

  defp event_metric(%Message{text: text}, {hs, ls, c}, autonumber) do
    new_c = c + 1
    eff = effective_label(text, if(autonumber, do: new_c))
    {[@event_row_h | hs], [eff | ls], new_c}
  end

  defp event_metric(_ev, {hs, ls, c}, _auto), do: {[0 | hs], ["" | ls], c}

  defp compute_gap_mins(diagram, flat, labels, n, min_gap) when n > 1 do
    gap_mins = List.duplicate(min_gap, n - 1)

    flat
    |> Enum.zip(labels)
    |> Enum.reduce(gap_mins, fn {ev, label}, gaps ->
      expand_gaps_for_event(ev, label, gaps, diagram)
    end)
  end

  defp compute_gap_mins(_diagram, _flat, _labels, _n, _min_gap), do: []

  defp expand_gaps_for_event(%Note{} = note, _label, gaps, diagram) do
    expand_gaps_for_note(note, gaps, diagram)
  end

  defp expand_gaps_for_event(%Message{} = msg, eff_label, gaps, diagram) do
    si = participant_index(diagram, msg.from)
    ti = participant_index(diagram, msg.to)
    expand_message_gaps(gaps, si, ti, eff_label)
  end

  defp expand_gaps_for_event(_ev, _label, gaps, _diagram), do: gaps

  defp expand_message_gaps(gaps, si, ti, _label) when si < 0 or ti < 0 or si == ti, do: gaps

  defp expand_message_gaps(gaps, si, ti, label) do
    {lo, hi} = {min(si, ti), max(si, ti)}
    per_gap = div(String.length(label) + 6 + hi - lo - 1, hi - lo)
    expand_range(gaps, lo, hi, per_gap)
  end

  defp expand_gaps_for_note(%Note{position: :right_of} = note, gaps, diagram) do
    note_width = max_note_line_width(note.text) + 4
    n = length(diagram.participants)

    Enum.reduce(note.participants, gaps, fn pid, acc ->
      pi = participant_index(diagram, pid)
      if pi >= 0 and pi < n - 1, do: List.update_at(acc, pi, &max(&1, note_width + 4)), else: acc
    end)
  end

  defp expand_gaps_for_note(%Note{position: :left_of} = note, gaps, diagram) do
    note_width = max_note_line_width(note.text) + 4

    Enum.reduce(note.participants, gaps, fn pid, acc ->
      pi = participant_index(diagram, pid)
      if pi > 0, do: List.update_at(acc, pi - 1, &max(&1, note_width + 4)), else: acc
    end)
  end

  defp expand_gaps_for_note(%Note{position: :over, participants: [p1, p2]} = note, gaps, diagram) do
    note_width = max_note_line_width(note.text) + 4
    p1i = participant_index(diagram, p1)
    p2i = participant_index(diagram, p2)
    expand_spanning_note_gaps(gaps, p1i, p2i, note_width)
  end

  defp expand_gaps_for_note(_note, gaps, _diagram), do: gaps

  defp expand_spanning_note_gaps(gaps, p1i, p2i, _nw) when p1i < 0 or p2i < 0, do: gaps

  defp expand_spanning_note_gaps(gaps, p1i, p2i, note_width) do
    {lo, hi} = {min(p1i, p2i), max(p1i, p2i)}
    per_gap = div(note_width + hi - lo - 1, hi - lo)
    expand_range(gaps, lo, hi, per_gap)
  end

  defp expand_range(gaps, lo, hi, per_gap) do
    Enum.reduce(lo..(hi - 1)//1, gaps, fn g, acc ->
      List.update_at(acc, g, &max(&1, per_gap))
    end)
  end

  defp build_col_centers(box_widths, gap_mins, n) when n > 0 do
    first = div(hd(box_widths), 2) + 1

    {centers, _} =
      Enum.reduce(1..(n - 1)//1, {[first], first}, fn i, {cs, prev} ->
        gap = Enum.at(gap_mins, i - 1) || @min_gap
        center = prev + gap
        {[center | cs], center}
      end)

    Enum.reverse(centers)
  end

  defp build_col_centers(_bw, _gm, _n), do: []

  defp compute_max_right(col_centers, box_widths, flat, diagram) do
    base = max_right_base(col_centers, box_widths)
    Enum.reduce(flat, base, &max_right_for_event(&1, &2, col_centers, diagram))
  end

  defp max_right_base([], _box_widths), do: 20

  defp max_right_base(col_centers, box_widths) do
    List.last(col_centers) + div(List.last(box_widths), 2) + 2
  end

  defp max_right_for_event(%Message{from: from, to: to} = msg, acc, col_centers, diagram)
       when from == to do
    si = participant_index(diagram, from)

    if si < 0,
      do: acc,
      else: max(acc, Enum.at(col_centers, si) + max(Utils.display_width(msg.text) + 4, 8) + 1)
  end

  defp max_right_for_event(%Note{position: :right_of} = note, acc, col_centers, diagram) do
    nw = max_note_line_width(note.text) + 4

    Enum.reduce(note.participants, acc, fn pid, a ->
      pi = participant_index(diagram, pid)
      if pi >= 0, do: max(a, Enum.at(col_centers, pi) + 2 + nw + 1), else: a
    end)
  end

  defp max_right_for_event(_ev, acc, _col_centers, _diagram), do: acc

  defp build_row_offsets(event_heights, start) do
    {offsets, _} =
      Enum.reduce(event_heights, {[], start}, fn h, {os, cum} -> {[cum | os], cum + h} end)

    Enum.reverse(offsets)
  end

  # Event flattening

  defp flatten_events(events, depth \\ 0) do
    Enum.flat_map(events, &flatten_event(&1, depth))
  end

  defp flatten_event(%Block{} = block, depth) do
    start = [%BlockStart{block: block, depth: depth}]
    body = flatten_events(block.events, depth + 1)

    sections =
      Enum.flat_map(block.sections, fn section ->
        [
          %BlockSectionBreak{section: section, depth: depth}
          | flatten_events(section.events, depth + 1)
        ]
      end)

    start ++ body ++ sections ++ [%BlockEnd{block: block, depth: depth}]
  end

  defp flatten_event(other, _depth), do: [other]

  # Activation ranges

  defp compute_activation_ranges(flat, row_offsets) do
    {open, ranges} =
      flat
      |> Enum.zip(row_offsets)
      |> Enum.reduce({%{}, %{}}, &track_activation/2)

    max_row = if row_offsets == [], do: 0, else: Enum.max(row_offsets) + 1
    close_open_activations(open, ranges, max_row)
  end

  defp track_activation({%Activate{participant: pid, active: true}, row}, {open, ranges}) do
    stack = Map.get(open, pid, [])
    {Map.put(open, pid, [row | stack]), ranges}
  end

  defp track_activation({%Activate{participant: pid, active: false}, row}, {open, ranges}) do
    close_activation(open, ranges, pid, row)
  end

  defp track_activation(_other, acc), do: acc

  defp close_activation(open, ranges, pid, row) do
    case Map.get(open, pid, []) do
      [start | rest] ->
        existing = Map.get(ranges, pid, [])
        {Map.put(open, pid, rest), Map.put(ranges, pid, [{start, row} | existing])}

      [] ->
        {open, ranges}
    end
  end

  defp close_open_activations(open, ranges, max_row) do
    Enum.reduce(open, ranges, fn {pid, starts}, acc ->
      extra = Enum.map(starts, fn s -> {s, max_row} end)
      Map.update(acc, pid, extra, &(extra ++ &1))
    end)
  end

  defp activated?(ranges, pid, row) do
    ranges |> Map.get(pid, []) |> Enum.any?(fn {s, e} -> s <= row and row <= e end)
  end

  defp compute_destroyed(flat, row_offsets) do
    flat
    |> Enum.zip(row_offsets)
    |> Enum.reduce(%{}, fn
      {%Destroy{participant: pid}, row}, acc -> Map.put_new(acc, pid, row)
      _other, acc -> acc
    end)
  end

  # Drawing: participant headers

  defp draw_participant_headers(canvas, diagram, layout, cs, use_ascii) do
    diagram.participants
    |> Enum.with_index()
    |> Enum.reduce(canvas, fn {p, i}, acc ->
      cx = Enum.at(layout.col_centers, i)
      bw = Enum.at(layout.box_widths, i)
      draw_participant_header(acc, cx, bw, layout.header_height, p, cs, use_ascii)
    end)
  end

  defp draw_participant_header(
         canvas,
         cx,
         _bw,
         header_height,
         %Participant{type: :actor} = p,
         _cs,
         _use_ascii
       ) do
    y = @top_margin + (header_height - @actor_height)

    canvas
    |> Canvas.put(cx, y, "O", merge: false, style: "node")
    |> Canvas.put(cx - 1, y + 1, "/", merge: false, style: "node")
    |> Canvas.put(cx, y + 1, "|", merge: false, style: "node")
    |> Canvas.put(cx + 1, y + 1, "\\", merge: false, style: "node")
    |> Canvas.put(cx - 1, y + 2, "/", merge: false, style: "node")
    |> Canvas.put(cx + 1, y + 2, "\\", merge: false, style: "node")
    |> Canvas.put_text(cx - div(Utils.display_width(p.label), 2), y + 4, p.label, style: "label")
  end

  defp draw_participant_header(canvas, cx, bw, header_height, p, cs, _use_ascii) do
    box_y = @top_margin + (header_height - @box_height)
    Shapes.draw_rectangle(canvas, cx - div(bw, 2), box_y, bw, @box_height, p.label, cs)
  end

  # Drawing: lifelines

  defp draw_lifelines(canvas, diagram, layout, activation_ranges, destroyed, use_ascii) do
    lifeline_start = @top_margin + layout.header_height
    lifeline_end = layout.height - @bottom_margin - 1
    chars = {if(use_ascii, do: ":", else: "┆"), if(use_ascii, do: "[", else: "║")}

    diagram.participants
    |> Enum.with_index()
    |> Enum.reduce(canvas, fn {p, i}, acc ->
      cx = Enum.at(layout.col_centers, i)
      end_row = Map.get(destroyed, p.id, lifeline_end + 1)

      draw_lifeline(
        acc,
        cx,
        lifeline_start,
        min(end_row - 1, lifeline_end),
        p.id,
        activation_ranges,
        chars
      )
    end)
  end

  defp draw_lifeline(canvas, cx, from, to, pid, activation_ranges, {normal, active}) do
    Enum.reduce(from..to//1, canvas, fn r, c ->
      ch = if activated?(activation_ranges, pid, r), do: active, else: normal
      Canvas.put(c, cx, r, ch, merge: false, style: "edge")
    end)
  end

  # Drawing: block side borders

  defp draw_block_side_borders(canvas, flat, layout, cs) do
    col_centers = layout.col_centers

    {canvas, _stack} =
      flat
      |> Enum.zip(layout.row_offsets)
      |> Enum.reduce({canvas, []}, fn
        {%BlockStart{depth: depth}, row}, {c, stack} ->
          bounds = block_frame_bounds(col_centers, depth)
          {c, [{bounds, row} | stack]}

        {%BlockEnd{}, row}, {c, [{bounds, start_row} | rest]} ->
          c = draw_border_sides(c, bounds, start_row + 1, row - 1, layout.width, cs)
          {c, rest}

        _other, acc ->
          acc
      end)

    canvas
  end

  defp draw_border_sides(canvas, {left, right}, from, to, width, cs) when from <= to do
    Enum.reduce(from..to//1, canvas, fn r, acc ->
      acc = Canvas.put(acc, left, r, cs.box.vertical, merge: false, style: "node")

      if right < width,
        do: Canvas.put(acc, right, r, cs.box.vertical, merge: false, style: "node"),
        else: acc
    end)
  end

  defp draw_border_sides(canvas, _bounds, _from, _to, _width, _cs), do: canvas

  # Drawing: events

  defp draw_events(canvas, diagram, flat, layout, cs, use_ascii) do
    {canvas, _counter} =
      flat
      |> Enum.zip(layout.row_offsets)
      |> Enum.reduce({canvas, 0}, fn {ev, row}, {c, counter} ->
        draw_event(ev, row, c, counter, diagram, layout, cs, use_ascii)
      end)

    canvas
  end

  defp draw_event(%Activate{}, _row, canvas, counter, _d, _l, _cs, _ascii), do: {canvas, counter}

  defp draw_event(
         %Destroy{participant: pid},
         row,
         canvas,
         counter,
         diagram,
         layout,
         _cs,
         use_ascii
       ) do
    canvas = draw_destroy(canvas, pid, row, diagram, layout, use_ascii)
    {canvas, counter}
  end

  defp draw_event(%Note{} = note, row, canvas, counter, diagram, layout, cs, _use_ascii) do
    {draw_note(canvas, note, row, layout.col_centers, diagram, cs), counter}
  end

  defp draw_event(%BlockStart{} = ev, row, canvas, counter, _d, layout, cs, _ascii) do
    {draw_block_start(canvas, ev, row, layout, cs), counter}
  end

  defp draw_event(%BlockSectionBreak{} = ev, row, canvas, counter, _d, layout, cs, use_ascii) do
    {draw_block_section(canvas, ev, row, layout, cs, use_ascii), counter}
  end

  defp draw_event(%BlockEnd{} = ev, row, canvas, counter, _d, layout, cs, _ascii) do
    {draw_block_end(canvas, ev, row, layout, cs), counter}
  end

  defp draw_event(%Message{} = msg, row, canvas, counter, diagram, layout, _cs, use_ascii) do
    new_counter = counter + 1
    label = effective_label(msg.text, if(diagram.autonumber, do: new_counter))
    canvas = draw_message_dispatch(canvas, msg, label, row, diagram, layout, use_ascii)
    {canvas, new_counter}
  end

  defp draw_event(_ev, _row, canvas, counter, _d, _l, _cs, _ascii), do: {canvas, counter}

  defp draw_destroy(canvas, pid, row, diagram, layout, use_ascii) do
    pi = participant_index(diagram, pid)

    if pi < 0,
      do: canvas,
      else:
        Canvas.put(
          canvas,
          Enum.at(layout.col_centers, pi),
          row,
          if(use_ascii, do: "X", else: "╳"),
          merge: false,
          style: "arrow"
        )
  end

  defp draw_message_dispatch(canvas, msg, label, row, diagram, layout, use_ascii) do
    si = participant_index(diagram, msg.from)
    ti = participant_index(diagram, msg.to)

    cond do
      si < 0 or ti < 0 ->
        canvas

      si == ti ->
        draw_self_message(canvas, Enum.at(layout.col_centers, si), row, msg, label, use_ascii)

      true ->
        draw_message(
          canvas,
          Enum.at(layout.col_centers, si),
          Enum.at(layout.col_centers, ti),
          row,
          msg,
          label,
          use_ascii
        )
    end
  end

  # Drawing: messages

  defp draw_message(canvas, src_col, tgt_col, row, msg, label, use_ascii) do
    left = min(src_col, tgt_col)
    right = max(src_col, tgt_col)
    h_char = line_char(msg.line_type, use_ascii)

    canvas =
      Enum.reduce((left + 1)..(right - 1)//1, canvas, fn c, acc ->
        Canvas.put(acc, c, row, h_char, merge: false, style: "edge")
      end)

    canvas =
      draw_arrow_endpoints(
        canvas,
        left,
        right,
        tgt_col > src_col,
        row,
        msg.arrow_type,
        h_char,
        use_ascii
      )

    maybe_put_label(canvas, label, left + 2, row - 1)
  end

  defp draw_arrow_endpoints(canvas, left, right, going_right, row, :arrow, h_char, use_ascii) do
    {arrow_col, line_col} = if going_right, do: {right, left}, else: {left, right}
    arrow = if going_right, do: arrow_right(use_ascii), else: arrow_left(use_ascii)

    canvas
    |> Canvas.put(arrow_col, row, arrow, merge: false, style: "arrow")
    |> Canvas.put(line_col, row, h_char, merge: false, style: "edge")
  end

  defp draw_arrow_endpoints(canvas, left, right, going_right, row, :cross, h_char, _ascii) do
    {x_col, line_col} = if going_right, do: {right, left}, else: {left, right}

    canvas
    |> Canvas.put(x_col, row, "x", merge: false, style: "arrow")
    |> Canvas.put(line_col, row, h_char, merge: false, style: "edge")
  end

  defp draw_arrow_endpoints(canvas, left, right, going_right, row, :async, h_char, _ascii) do
    {async_col, async_ch, line_col} =
      if going_right, do: {right, ")", left}, else: {left, "(", right}

    canvas
    |> Canvas.put(async_col, row, async_ch, merge: false, style: "arrow")
    |> Canvas.put(line_col, row, h_char, merge: false, style: "edge")
  end

  defp draw_arrow_endpoints(canvas, left, right, _going_right, row, _open, h_char, _ascii) do
    canvas
    |> Canvas.put(left, row, h_char, merge: false, style: "edge")
    |> Canvas.put(right, row, h_char, merge: false, style: "edge")
  end

  defp draw_self_message(canvas, col, row, msg, label, use_ascii) do
    loop_width = max(Utils.display_width(label) + 4, 8)
    h_char = line_char(msg.line_type, use_ascii)
    v_char = vline_char(msg.line_type, use_ascii)
    right_col = col + loop_width - 1

    canvas
    |> fill_h(col + 1, right_col - 1, row, h_char)
    |> Canvas.put(right_col, row + 1, v_char, merge: false, style: "edge")
    |> fill_h(col + 1, right_col - 1, row + 1, h_char)
    |> draw_self_arrow(col, row + 1, msg.arrow_type, h_char, use_ascii)
    |> draw_self_corners(right_col, row, use_ascii)
    |> maybe_put_label(label, col + 2, row - 1)
  end

  defp draw_self_arrow(canvas, col, row, :arrow, _h_char, use_ascii) do
    Canvas.put(canvas, col, row, arrow_left(use_ascii), merge: false, style: "arrow")
  end

  defp draw_self_arrow(canvas, col, row, :cross, _h_char, _ascii) do
    Canvas.put(canvas, col, row, "x", merge: false, style: "arrow")
  end

  defp draw_self_arrow(canvas, col, row, :async, _h_char, _ascii) do
    Canvas.put(canvas, col, row, "(", merge: false, style: "arrow")
  end

  defp draw_self_arrow(canvas, col, row, _open, h_char, _ascii) do
    Canvas.put(canvas, col, row, h_char, merge: false, style: "edge")
  end

  defp draw_self_corners(canvas, right_col, row, true) do
    canvas
    |> Canvas.put(right_col, row, "+", merge: false, style: "edge")
    |> Canvas.put(right_col, row + 1, "+", merge: false, style: "edge")
  end

  defp draw_self_corners(canvas, right_col, row, false) do
    canvas
    |> Canvas.put(right_col, row, "┐", merge: false, style: "edge")
    |> Canvas.put(right_col, row + 1, "┘", merge: false, style: "edge")
  end

  # Drawing: notes

  defp draw_note(canvas, %Note{} = note, row, col_centers, diagram, cs) do
    lines = note_lines(note.text)
    note_width = max_note_line_width(note.text) + 4
    note_height = length(lines) + 2

    case note_x_position(note, note_width, col_centers, diagram) do
      nil -> canvas
      x -> Shapes.draw_rectangle(canvas, max(0, x), row, note_width, note_height, note.text, cs)
    end
  end

  defp note_x_position(%Note{position: :right_of, participants: [pid | _]}, _nw, centers, diagram) do
    pi = participant_index(diagram, pid)
    if pi >= 0, do: Enum.at(centers, pi) + 2
  end

  defp note_x_position(%Note{position: :left_of, participants: [pid | _]}, nw, centers, diagram) do
    pi = participant_index(diagram, pid)
    if pi >= 0, do: Enum.at(centers, pi) - 2 - nw
  end

  defp note_x_position(%Note{position: :over, participants: [p1, p2]}, nw, centers, diagram) do
    over_two_note_x(diagram, p1, p2, nw, centers)
  end

  defp note_x_position(%Note{position: :over, participants: [pid | _]}, nw, centers, diagram) do
    pi = participant_index(diagram, pid)
    if pi >= 0, do: Enum.at(centers, pi) - div(nw, 2)
  end

  defp note_x_position(_note, _nw, _centers, _diagram), do: nil

  defp over_two_note_x(diagram, p1, p2, nw, centers) do
    p1i = participant_index(diagram, p1)
    p2i = participant_index(diagram, p2)

    if p1i >= 0 and p2i >= 0 do
      center = div(Enum.at(centers, p1i) + Enum.at(centers, p2i), 2)
      span = abs(Enum.at(centers, p1i) - Enum.at(centers, p2i)) + 4
      center - div(max(nw, span), 2)
    end
  end

  # Drawing: blocks

  defp block_frame_bounds(col_centers, depth) do
    indent = depth * 2

    left =
      if col_centers == [],
        do: indent,
        else: max(0, hd(col_centers) - 6 + indent)

    right =
      if col_centers == [],
        do: 20 - indent,
        else: List.last(col_centers) + 6 - indent

    {left, right}
  end

  defp draw_block_start(canvas, %BlockStart{block: block, depth: depth}, row, layout, cs) do
    {left, right} = block_frame_bounds(layout.col_centers, depth)

    canvas
    |> Canvas.put(left, row, cs.box.top_left, merge: false, style: "node")
    |> fill_h_styled(left + 1, min(right - 1, layout.width - 1), row, cs.box.horizontal, "node")
    |> put_if(right < layout.width, right, row, cs.box.top_right, "node")
    |> draw_block_label_row(left, right, row + 1, layout, cs, block)
  end

  defp draw_block_label_row(canvas, _left, _right, label_row, %Layout{height: h}, _cs, _block)
       when label_row >= h,
       do: canvas

  defp draw_block_label_row(canvas, left, right, label_row, layout, cs, block) do
    label = if block.label != "", do: "[#{block.kind}] #{block.label}", else: "[#{block.kind}]"

    canvas
    |> Canvas.put(left, label_row, cs.box.vertical, merge: false, style: "node")
    |> put_if(right < layout.width, right, label_row, cs.box.vertical, "node")
    |> Canvas.put_text(left + 1, label_row, label, style: "edge_label")
  end

  defp draw_block_section(
         canvas,
         %BlockSectionBreak{section: section, depth: depth},
         row,
         layout,
         cs,
         use_ascii
       ) do
    {left, right} = block_frame_bounds(layout.col_centers, depth)
    dash = if(use_ascii, do: ".", else: "┄")

    canvas
    |> Canvas.put(left, row, cs.box.vertical, merge: false, style: "node")
    |> fill_h_styled(left + 1, min(right - 1, layout.width - 1), row, dash, "node")
    |> put_if(right < layout.width, right, row, cs.box.vertical, "node")
    |> maybe_put_section_label(section, left + 2, row)
  end

  defp maybe_put_section_label(canvas, %BlockSection{label: ""}, _col, _row), do: canvas

  defp maybe_put_section_label(canvas, section, col, row) do
    Canvas.put_text(canvas, col, row, "[#{section.label}]", style: "edge_label")
  end

  defp draw_block_end(canvas, %BlockEnd{depth: depth}, row, layout, cs) do
    {left, right} = block_frame_bounds(layout.col_centers, depth)

    canvas
    |> Canvas.put(left, row, cs.box.bottom_left, merge: false, style: "node")
    |> fill_h_styled(left + 1, min(right - 1, layout.width - 1), row, cs.box.horizontal, "node")
    |> put_if(right < layout.width, right, row, cs.box.bottom_right, "node")
  end

  # Helpers

  defp participant_index(%SequenceDiagram{participants: ps}, pid) do
    Enum.find_index(ps, &(&1.id == pid)) || -1
  end

  defp effective_label(text, nil), do: text
  defp effective_label("", number), do: "#{number}"
  defp effective_label(text, number), do: "#{number}: #{text}"

  defp note_lines(text) do
    if String.contains?(text, "\n"), do: String.split(text, "\n"), else: [text]
  end

  defp max_note_line_width(text) do
    text |> note_lines() |> Enum.reduce(0, fn l, acc -> max(acc, Utils.display_width(l)) end)
  end

  defp line_char(:dotted, true), do: "."
  defp line_char(:dotted, false), do: "┄"
  defp line_char(_solid, true), do: "-"
  defp line_char(_solid, false), do: "─"

  defp vline_char(:dotted, true), do: ":"
  defp vline_char(:dotted, false), do: "┆"
  defp vline_char(_solid, true), do: "|"
  defp vline_char(_solid, false), do: "│"

  defp arrow_right(true), do: ">"
  defp arrow_right(false), do: "►"
  defp arrow_left(true), do: "<"
  defp arrow_left(false), do: "◄"

  defp fill_h(canvas, from, to, _row, _ch) when from > to, do: canvas

  defp fill_h(canvas, from, to, row, ch) do
    Enum.reduce(from..to//1, canvas, fn c, acc ->
      Canvas.put(acc, c, row, ch, merge: false, style: "edge")
    end)
  end

  defp fill_h_styled(canvas, from, to, _row, _ch, _style) when from > to, do: canvas

  defp fill_h_styled(canvas, from, to, row, ch, style) do
    Enum.reduce(from..to//1, canvas, fn c, acc ->
      Canvas.put(acc, c, row, ch, merge: false, style: style)
    end)
  end

  defp put_if(canvas, true, col, row, ch, style) do
    Canvas.put(canvas, col, row, ch, merge: false, style: style)
  end

  defp put_if(canvas, false, _col, _row, _ch, _style), do: canvas

  defp maybe_put_label(canvas, "", _col, _row), do: canvas

  defp maybe_put_label(canvas, label, col, row),
    do: Canvas.put_text(canvas, col, row, label, style: "edge_label")

  defp charset_from_opts(opts) do
    case Keyword.get(opts, :charset, :unicode) do
      :ascii -> Charset.ascii()
      _ -> Charset.unicode()
    end
  end
end
