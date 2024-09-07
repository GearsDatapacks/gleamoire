import commonmark
import commonmark/ast
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import gleam_community/ansi

/// Some additonal context to improve styling for vertain cases
type MdContext {
  /// The default context. Default styling rules apply
  None
  /// Text is already coloured, so we don't want to re-colour it.
  /// This improves the styling of, for example, inline code within a header.
  Coloured
}

pub fn render(md: String) -> String {
  let parsed = commonmark.parse(md)
  render_nodes(parsed.blocks, parsed.references, None)
}

fn render_nodes(
  nodes: List(ast.BlockNode),
  references: Dict(String, ast.Reference),
  context: MdContext,
) -> String {
  nodes
  |> list.map(render_node(_, references, context))
  |> string.join("\n\n")
}

fn render_node(
  node: ast.BlockNode,
  references: Dict(String, ast.Reference),
  context: MdContext,
) -> String {
  case node {
    ast.AlertBlock(level, nodes) ->
      render_nodes(nodes, references, Coloured)
      |> colour_alert(level)
    ast.BlockQuote(nodes) ->
      render_nodes(nodes, references, context)
      |> string.split("\n")
      // Indent each line
      |> list.map(fn(line) { "  " <> line })
      |> string.join("\n")
      |> ansi.italic
    ast.CodeBlock(contents:, ..) ->
      // Prefixing with a newline allows the background colour to cover the entire
      // first line, which it doesn't otherwise.
      // We also trim trailing whitespace, because the markdown parser seems to leave in
      // the newline beweet the end of the code and the closing "```".
      { "\n" <> contents |> string.trim_right } |> ansi.bg_hex(0x1a1a1a)
    ast.Heading(level, nodes) ->
      render_inline_nodes(nodes, references, Coloured)
      |> style_heading(level)
    ast.HorizontalBreak -> "\n"
    ast.HtmlBlock(html) -> html
    ast.OrderedList(contents:, start:, ..) ->
      contents
      |> list.index_map(fn(item, index) {
        let item = case item {
          ast.ListItem(nodes) | ast.TightListItem(nodes) ->
            render_nodes(nodes, references, context)
        }
        // Indenting these by one space seems to make them easier to ready and look better
        " " <> ansi.bold(int.to_string(index + start) <> ". ") <> item
      })
      |> string.join("\n")
    ast.Paragraph(nodes) -> render_inline_nodes(nodes, references, context)
    ast.UnorderedList(contents:, ..) ->
      contents
      |> list.map(fn(item) {
        let item = case item {
          ast.ListItem(nodes) | ast.TightListItem(nodes) ->
            render_nodes(nodes, references, context)
        }

        ansi.bold(" • ") <> item
      })
      |> string.join("\n")
  }
}

fn render_inline_nodes(
  nodes: List(ast.InlineNode),
  references: Dict(String, ast.Reference),
  context: MdContext,
) -> String {
  nodes
  |> list.map(render_inline_node(_, references, context))
  |> string.join("")
}

fn render_inline_node(
  node: ast.InlineNode,
  references: Dict(String, ast.Reference),
  context: MdContext,
) -> String {
  case node {
    ast.CodeSpan(contents) ->
      case context {
        Coloured -> contents |> ansi.bg_hex(0x252525) |> ansi.bold
        None -> contents |> ansi.black |> ansi.bg_hex(0x111111) |> ansi.bold
      }
    ast.EmailAutolink(text) -> text
    ast.Emphasis(nodes, _) ->
      nodes
      |> render_inline_nodes(references, context)
      |> ansi.italic
    ast.HardLineBreak -> "\n"
    ast.HtmlInline(html) -> html
    // We can't render images in the terminal so instead we just reconstruct the markdown
    ast.Image(alt:, href:, ..) ->
      "![" <> alt <> "](" <> href |> ansi.blue |> ansi.underline <> ")"
    // Hyperlinks are widely unsupported by terminals, so again we print in md format
    ast.Link(contents:, href:, ..) ->
      "["
      <> render_inline_nodes(contents, references, context)
      <> "]("
      <> href |> ansi.blue |> ansi.underline
      <> ")"
    ast.PlainText(text) -> text
    ast.ReferenceImage(alt, ref) -> {
      "![" <> alt <> "](" <> get_href(references, ref) <> ")"
    }
    ast.ReferenceLink(contents:, ref:) -> {
      "["
      <> render_inline_nodes(contents, references, context)
      <> "]("
      <> get_href(references, ref)
      <> ")"
    }
    ast.SoftLineBreak -> "\n"
    ast.StrikeThrough(nodes) ->
      nodes
      |> render_inline_nodes(references, context)
      |> ansi.strikethrough
    ast.StrongEmphasis(nodes, marker) -> {
      let text = render_inline_nodes(nodes, references, context)
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

fn style_heading(text: String, level: Int) -> String {
  case level {
    1 -> text |> ansi.cyan |> ansi.bold |> ansi.underline
    2 -> text |> ansi.yellow |> ansi.bold |> ansi.underline
    3 -> text |> ansi.magenta |> ansi.bold
    4 -> text |> ansi.pink |> ansi.bold
    _ -> text
  }
}
