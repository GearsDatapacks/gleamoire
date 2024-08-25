import gleam/dict
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/package_interface as pi
import gleam/result
import gleam/string
import gleamoire/args
import gleamoire/error

pub fn document_module(
  module_name: String,
  module_interface: pi.Module,
) -> Result(String, error.Error) {
  let simple = simplify_module_interface(module_interface)
  let available_modules =
    "Help on module `"
    <> module_name
    <> "`:\n\n"
    <> "Available items\n"
    <> "> Types\n"
    <> string.join(
      list.map(dict.keys(simple.types), string.append("  - ", _)),
      "\n",
    )
    <> "\n\n"
    <> "> Values\n"
    <> string.join(
      list.map(dict.keys(simple.values), string.append("  - ", _)),
      "\n",
    )
  let module_documentation = case module_interface.documentation {
    [] -> ""
    // TODO: https://trello.com/c/qXFKt5Q7  Might open README.md if toplevel documentation
    doc ->
      "\n\nDocumentation for module `"
      <> module_name
      <> "`\n"
      <> string.join(doc, "\n")
  }

  Ok(available_modules <> module_documentation)
}

pub fn document_item(
  name: String,
  module_name: String,
  module_interface: pi.Module,
  print_mode: args.PrintMode,
) -> Result(String, error.Error) {
  let simple = simplify_module_interface(module_interface)
  let type_ = dict.get(simple.types, name)
  let value = dict.get(simple.values, name)

  case type_, value {
    Error(_), Error(_) ->
      Error(error.InterfaceError(
        "No item has been found with the name " <> name,
      ))
    Ok(type_docs), Error(_) -> Ok(type_docs)
    Error(_), Ok(value_docs) -> Ok(value_docs)
    Ok(type_docs), Ok(value_docs) ->
      case print_mode {
        args.Unspecified ->
          Error(error.InterfaceError(
            "There is both a type and value with that name. Please specify -t or -v to print the one you want",
          ))
        args.Type -> Ok(type_docs)
        args.Value -> Ok(value_docs)
      }
  }
  |> result.map(render_item(_, module_name))
}

fn render_item(item: SimpleItem, module_name: String) -> String {
  "Documentation for item `"
  <> item.name
  <> "` in `"
  <> module_name
  <> "`:\n\n"
  <> item.representation
  <> case item.documentation {
    None | Some("") -> ""
    Some(docs) -> "\n\n" <> docs <> "\n"
  }
  <> case item.deprecation {
    None | Some("") -> ""
    Some(deprecation) ->
      "\n\n/!\\ This item has been deprecated :\n" <> deprecation
  }
}

type TypeInterface {
  Type(pi.TypeDefinition)
  Alias(pi.TypeAlias)
}

type ValueInterface {
  Constant(pi.Constant)
  Function(pi.Function)
  Constructor(cons: pi.TypeConstructor, parent: SimpleItem)
}

type SimpleItem {
  SimpleItem(
    name: String,
    representation: String,
    documentation: Option(String),
    deprecation: Option(String),
  )
}

type SimpleModule {
  SimpleModule(
    types: dict.Dict(String, SimpleItem),
    values: dict.Dict(String, SimpleItem),
  )
}

fn simplify_module_interface(interface: pi.Module) {
  let types =
    interface.types
    |> dict.map_values(fn(_, type_) { Type(type_) })
  let types =
    dict.merge(
      types,
      interface.type_aliases
        |> dict.map_values(fn(_, alias) { Alias(alias) }),
    )
    |> dict.map_values(simplify_type)

  let values =
    interface.constants
    |> dict.map_values(fn(_, constant) { Constant(constant) })
  let values =
    dict.merge(
      values,
      interface.functions
        |> dict.map_values(fn(_, function) { Function(function) }),
    )
  let constructors =
    dict.fold(interface.types, dict.new(), fn(acc, type_name, type_) {
      dict.merge(
        acc,
        type_.constructors
          |> list.map(fn(cons) {
            #(
              cons.name,
              Constructor(cons, simplify_type(type_name, Type(type_))),
            )
          })
          |> dict.from_list(),
      )
    })
  let values =
    dict.merge(values, constructors) |> dict.map_values(simplify_value)

  SimpleModule(types:, values:)
}

fn simplify_type(name: String, type_: TypeInterface) -> SimpleItem {
  let documentation = case type_ {
    Type(t) -> t.documentation
    Alias(a) -> a.documentation
  }
  let render_type_parameters = fn(p) {
    case p {
      0 -> ""
      n ->
        "("
        <> n
        |> list.range(0, _)
        |> list.map(get_variable_symbol)
        |> string.join(", ")
        <> ")"
    }
  }
  let representation = case type_ {
    Type(t) ->
      "pub type "
      <> name
      <> t.parameters |> render_type_parameters
      <> " {\n  "
      <> t.constructors |> list.map(render_constructor) |> string.join("\n  ")
      <> "\n}"
    Alias(a) ->
      "type "
      <> name
      <> a.parameters |> render_type_parameters
      <> " = "
      <> render_type(a.alias)
  }
  let deprecation = case type_ {
    Type(t) -> option.map(t.deprecation, fn(d: pi.Deprecation) { d.message })
    Alias(a) -> option.map(a.deprecation, fn(d: pi.Deprecation) { d.message })
  }
  SimpleItem(name:, documentation:, deprecation:, representation:)
}

fn simplify_value(name: String, value: ValueInterface) -> SimpleItem {
  let documentation = case value {
    Function(f) -> f.documentation
    Constant(c) -> c.documentation
    Constructor(c, _) -> c.documentation
  }
  let representation = case value {
    Function(f) -> render_function(name, f.parameters, Some(f.return))
    Constant(c) -> "pub const " <> name <> ": " <> render_type(c.type_)
    Constructor(c, parent_type) ->
      render_constructor(c)
      <> "\n\nThis constructor occurs in the following type:\n"
      <> parent_type.representation
  }
  let deprecation = case value {
    Function(f) ->
      option.map(f.deprecation, fn(d: pi.Deprecation) { d.message })
    Constant(c) ->
      option.map(c.deprecation, fn(d: pi.Deprecation) { d.message })
    Constructor(..) -> None
  }
  SimpleItem(name:, documentation:, deprecation:, representation:)
}

fn render_constructor(c: pi.TypeConstructor) -> String {
  let pi.TypeConstructor(_, name, parameters) = c
  name
  <> case parameters {
    [] -> ""
    params ->
      "(" <> params |> list.map(render_parameter) |> string.join(", ") <> ")"
  }
}

fn render_parameter(p: pi.Parameter) -> String {
  p.label |> option.map(fn(l) { l <> ": " }) |> option.unwrap("")
  <> render_type(p.type_)
}

fn render_function(
  name: String,
  parameters: List(pi.Parameter),
  return: Option(pi.Type),
) -> String {
  "pub fn "
  <> name
  <> "("
  <> parameters |> list.map(render_parameter) |> string.join(", ")
  <> ")\n  -> "
  <> return |> option.map(render_type) |> option.unwrap("Nil")
}

fn render_type(type_: pi.Type) -> String {
  case type_ {
    pi.Tuple(elements) ->
      "#(" <> elements |> list.map(render_type) |> string.join(", ") <> ")"
    pi.Fn(parameters, return) ->
      "fn("
      <> parameters |> list.map(render_type) |> string.join(", ")
      <> ") -> "
      <> render_type(return)
    pi.Variable(id) -> get_variable_symbol(id)
    pi.Named(name, _package, _module, parameters) ->
      name
      <> case parameters {
        [] -> ""
        items ->
          "(" <> items |> list.map(render_type) |> string.join(", ") <> ")"
      }
  }
}

fn get_variable_symbol(id: Int) -> String {
  let anchor = "a"
  let anchor_code =
    anchor
    |> string.to_utf_codepoints
    |> list.map(string.utf_codepoint_to_int)
    |> list.first
  anchor_code
  |> result.map(fn(x) { x + id })
  |> result.try(string.utf_codepoint)
  |> result.map(list.wrap)
  |> result.map(string.from_utf_codepoints)
  |> result.unwrap(anchor)
}
