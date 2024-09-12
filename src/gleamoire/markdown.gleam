import commonmark
import commonmark/ast
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/regex
import gleam/result
import gleam/string
import gleam_community/ansi

pub fn render(md: String) -> String {
  let parsed = commonmark.parse(md)
  render_nodes(parsed.blocks, parsed.references)
}

fn render_nodes(
  nodes: List(ast.BlockNode),
  references: Dict(String, ast.Reference),
) -> String {
  nodes
  |> list.map(render_node(_, references))
  |> string.join("\n\n")
}

fn max_int(values: List(Int)) -> Int {
  do_max_int(values, values |> list.first |> result.unwrap(0))
}

fn do_max_int(values: List(Int), max: Int) -> Int {
  case values {
    [] -> max
    [x, ..rest] -> do_max_int(rest, int.max(max, x))
  }
}

fn render_node(
  node: ast.BlockNode,
  references: Dict(String, ast.Reference),
) -> String {
  case node {
    ast.AlertBlock(level, nodes) ->
      render_nodes(nodes, references)
      |> colour_alert(level)
    ast.BlockQuote(nodes) ->
      render_nodes(nodes, references)
      |> string.split("\n")
      // Indent each line
      |> list.map(fn(line) { "| " <> line })
      |> string.join("\n")
      |> ansi.italic
      |> ansi.grey
    ast.CodeBlock(contents:, ..) -> {
      let lines =
        contents
        |> string.trim
        |> string.split("\n")
      let longest_line_length =
        lines
        |> list.map(string.length)
        |> max_int

      lines
      |> list.map(string.pad_right(_, to: longest_line_length, with: " "))
      |> string.join("\n")
      // Prefixing with a newline allows the background colour properly cover the
      // first line on some terminals, which it doesn't 
      |> string.append("\n", _)
      |> ansi.bg_hex(0x1a1a1a)
    }
    ast.Heading(level, nodes) ->
      render_inline_nodes(nodes, references)
      |> style_heading(level)
    ast.HorizontalBreak -> "\n--------------------\n"
    ast.HtmlBlock(html) -> {
      let assert Ok(regex) = "</?\\w+?>" |> regex.from_string
      regex |> regex.replace(html, "")
    }
    ast.OrderedList(contents:, start:, ..) ->
      contents
      |> list.index_map(fn(item, index) {
        let item = case item {
          ast.ListItem(nodes) | ast.TightListItem(nodes) ->
            render_nodes(nodes, references)
        }
        // Indenting these by one space seems to make them easier to ready and look better
        " " <> ansi.bold(int.to_string(index + start) <> ". ") <> item
      })
      |> string.join("\n")
    ast.Paragraph(nodes) -> render_inline_nodes(nodes, references)
    ast.UnorderedList(contents:, ..) ->
      contents
      |> list.map(fn(item) {
        let item = case item {
          ast.ListItem(nodes) | ast.TightListItem(nodes) ->
            render_nodes(nodes, references)
        }

        ansi.bold(" • ") <> item
      })
      |> string.join("\n")
  }
}

fn render_inline_nodes(
  nodes: List(ast.InlineNode),
  references: Dict(String, ast.Reference),
) -> String {
  nodes
  |> list.map(render_inline_node(_, references))
  |> string.join("")
}

fn render_inline_node(
  node: ast.InlineNode,
  references: Dict(String, ast.Reference),
) -> String {
  case node {
    ast.CodeSpan(contents) ->
      contents |> ansi.pink |> ansi.bg_hex(0x444444) |> ansi.bold
    ast.EmailAutolink(text) -> text
    ast.Emphasis(nodes, _) ->
      nodes
      |> render_inline_nodes(references)
      |> ansi.italic
    ast.HardLineBreak -> "\n"
    ast.HtmlInline(html) -> html
    // We can't render images in the terminal so instead we just reconstruct the markdown
    ast.Image(alt:, href:, ..) ->
      "![" <> alt <> "](" <> href |> ansi.blue |> ansi.underline <> ")"
    // Hyperlinks are widely unsupported by terminals, so again we print in md format
    ast.Link(contents:, href:, ..) ->
      "["
      <> render_inline_nodes(contents, references)
      <> "]("
      <> href |> ansi.blue |> ansi.underline
      <> ")"
    ast.PlainText(text) -> text
    ast.ReferenceImage(alt, ref) -> {
      "![" <> alt <> "](" <> get_href(references, ref) <> ")"
    }
    ast.ReferenceLink(contents:, ref:) -> {
      "["
      <> render_inline_nodes(contents, references)
      <> "]("
      <> get_href(references, ref)
      <> ")"
    }
    ast.SoftLineBreak -> "\n"
    ast.StrikeThrough(nodes) ->
      nodes
      |> render_inline_nodes(references)
      |> ansi.strikethrough
    ast.StrongEmphasis(nodes, marker) -> {
      let text = render_inline_nodes(nodes, references)
      case marker {
        ast.AsteriskEmphasisMarker -> text |> ansi.bold
        // `__` is often used to denote underline
        ast.UnderscoreEmphasisMarker -> text |> ansi.underline
      }
    }
    ast.UriAutolink(href) -> href |> ansi.blue |> ansi.underline
  }
}

fn get_href(references: Dict(String, ast.Reference), ref: String) -> String {
  references
  |> dict.get(ref)
  |> result.map(fn(ref) { ref.href })
  |> result.unwrap("")
  |> ansi.blue
  |> ansi.underline
}

fn colour_alert(text: String, level: ast.AlertLevel) -> String {
  case level {
    ast.CautionAlert -> text |> ansi.bg_bright_red
    ast.ImportantAlert -> text |> ansi.bg_bright_magenta
    ast.NoteAlert -> text |> ansi.bg_bright_blue
    ast.TipAlert -> text |> ansi.bg_pink
    ast.WarningAlert -> text |> ansi.bg_yellow
  }
}

pub fn style_heading(text: String, level: Int) -> String {
  case level {
    1 -> text |> ansi.blue |> ansi.bold |> ansi.underline
    2 -> text |> ansi.yellow |> ansi.bold |> ansi.underline
    3 -> text |> ansi.cyan |> ansi.underline
    4 -> text |> ansi.yellow |> ansi.bold
    5 -> text |> ansi.cyan
    6 -> text |> ansi.yellow
    _ -> text
  }
}