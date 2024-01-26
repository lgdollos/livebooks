defmodule LivebooksWeb.RenderLive do
  use LivebooksWeb, :live_view

  def mount(_url, _session, socket) do
    {:ok, assign(socket, md: "sql")}
  end

  def render(assigns) do
    ~H"""
    <div class="main w-full flex flex-col items-center">
      <.heading />
      <.main md={@md}/>
    </div>
    """
  end

  def heading(assigns) do
    ~H"""
    <div class="flex flex-row p-4 w-full bg-[#0F1828] text-indigo-200 text-sm gap-12 justify-center drop-shadow">
      <.heading_link title="sql murder mystery" value="sql" />
      <.heading_link title="think bayes (ch1)" value="bayes" />
      <.heading_link title="exercism" value="exercism" />
    </div>
    """
  end

  def heading_link(assigns) do
    ~H"""
    <div
      class="underline underline-offset-4 decoration-dotted decoration-[#8a93b9] cursor-pointer font-semibold"
      phx-click="change_md"
      phx-value-md={@value}
    >
      <%= @title %> →
    </div>
    """
  end

  def main(assigns) do
    ~H"""
    <div class="w-full lg:w-2/3 p-8">
      <%= read_md(@md) |> render_livemd() |> raw() %>
    </div>
    """
  end

  def read_md(filename) do
    File.read!("priv/static/livemd/#{filename}.livemd") |> to_string()
  end

  def handle_event("change_md", %{"md" => md}, socket) do
    {:noreply, assign(socket, md: md)}
  end

  def render_livemd(content) do
    content
    |> HtmlSanitizeEx.markdown_html()
    |> Earmark.as_html!()
    |> highlight_code_blocks()
    |> unescape_html()
  end

  def highlight_code_blocks(html) do
    Regex.replace(
      ~r/<pre><code(?:\s+class="(\w*)")?>([^<]*)<\/code><\/pre>/,
      html,
      &highlight_code_block(&1, &2, &3)
    )
  end

  def highlight_code_block(_, "elixir", code) do
    code
    |> unescape_html()
    |> IO.iodata_to_binary()
    |> Makeup.highlight()
  end

  def highlight_code_block(_, _lang, code) do
    cond do
      String.contains?(code, "[debug] QUERY") == true ->
        ~s(<pre class="query"><code class="makeup">#{code}</code></pre>)

      String.contains?(code, "[%{id") == true ->
        process_datatable(code)

      String.contains?(code, "Explorer.DataFrame") == true ->
        process_dataframe(code)

      String.contains?(code, "warning: ") == true ->
        ~s(<pre class="warning"><code class="makeup">#{code}</code></pre>)

      true ->
        ~s(<pre class="text"><code class="makeup">#{code}</code></pre>)
    end
  end

  def process_datatable(code) do
    dt = text2map(%{items: code}) |> render_datatable() |> Phoenix.HTML.Safe.to_iodata()
    ~s(#{dt})
  end

  def process_dataframe(code) do
    dt = render_datatable(parse_df(code)) |> Phoenix.HTML.Safe.to_iodata()
    ~s(#{dt})
  end

  def unescape_html(text) do
    text
    |> String.replace("&amp;", "&", global: true)
    |> String.replace("&lt;", "<", global: true)
    |> String.replace("&gt;", ">", global: true)
    |> String.replace("&quot;", "\"", global: true)
    |> String.replace("&#39;", "'", global: true)
  end

  def parse_df(dfstr) do
    [_exp, _plr | data] =
      dfstr
      |> unescape_html
      |> String.split("\n", trim: true)

    types = parse_types(data)
    series = parse_series(data)

    items =
      Enum.map(series, fn sublist ->
        Enum.zip(types, sublist)
        |> Enum.into(%{})
      end)

    %{items: items, cols: get_cols(items)}
  end

  def parse_types(data) do
    for d <- data, d != ">" do
      [meta | _] = String.split(d, "[", trim: true)

      meta
      |> String.split(" ", trim: true)
      |> List.first()
      |> String.to_atom()
    end
  end

  def parse_series(data) do
    for d <- data, d != ">" do
      [_ | dt] = String.split(d, "[", trim: true)

      data = List.first(dt)

      split =
        cond do
          String.at(data, 0) == "\"" -> String.split(data, ~r/",\s*"/, trim: true)
          true -> String.split(data, ", ", trim: true)
        end

      Enum.map(split, fn s ->
        s
        |> String.replace(~r/\\n/, "")
        |> String.replace(["\"", "]", ", ...", "\\"], "")
      end)
    end
    |> Enum.zip()
    |> Enum.map(fn t -> Tuple.to_list(t) end)
  end

  def text2map(assigns) do
    items = assigns.items |> unescape_html |> Code.eval_string() |> elem(0)
    %{items: items, cols: get_cols(items)}
  end

  def get_cols(items), do: items |> List.first() |> Map.keys()

  def render_datatable(assigns) do
    ~H"""
    <.table id="items" rows={assigns.items} class="datatable">
      <:col :let={item} :for={col <- assigns.cols} label={":#{col}"}><%= item[col] || "nil" %></:col>
    </.table>
    """
  end
end
