import gleam/dict
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/package_interface as pi
import gleam/result
import gleam/string
import gleamoire/args
import gleamoire/error

/// Starting character for type variable representation
/// can be modified to display a different sequence
const typevar_anchor = "a"

/// Generate documentation for a module
/// Include available submodules, types and values in addition to the documentation field
/// This is supposed to show as much information as the module page in the html docs
///
pub fn document_module(
  module_name: String,
  module_interface: pi.Module,
  package_interface: pi.Package,
) -> String {
  let simple =
    simplify_module_interface(module_name, module_interface, package_interface)
  let available_modules =
    "**Help on module `"
    <> module_name
    <> "`**:\n\n"
    <> list_or_empty(
      "Available submodules\n",
      simple.submodules |> list.map(fn(mod) { "- `" <> mod <> "`" }),
      "\n",
      "\n\n",
    )
    <> list_or_empty(
      "## Available items\n",
      [
        list_or_none(
          "### Types\n",
          list.map(dict.keys(simple.types), fn(mod) { "- `" <> mod <> "`" }),
          "\n",
          "",
        ),
        list_or_none(
          "### Values\n",
          list.map(dict.keys(simple.values), fn(mod) { "- `" <> mod <> "`" }),
          "\n",
          "",
        ),
      ]
        |> list.filter_map(option.to_result(_, Nil)),
      "\n\n",
      "\n\n",
    )

  // TODO: https://trello.com/c/qXFKt5Q7  Might open README.md if toplevel documentation
  let module_documentation =
    list_or_empty(
      "**Documentation for module `" <> module_name <> "`**\n",
      module_interface.documentation |> list.map(string.trim_right),
      "\n",
      "",
    )

  available_modules <> module_documentation
}

/// Render a list of strings
/// Feeding the empty list produces the empty string ""
///
fn list_or_empty(
  prefix: String,
  list: List(String),
  separator: String,
  suffix: String,
) -> String {
  list_or_none(prefix, list, separator, suffix) |> option.unwrap("")
}

/// Render a list of strings
/// Feeding the empty list produces None
///
fn list_or_none(
  prefix: String,
  list: List(String),
  separator: String,
  suffix: String,
) -> Option(String) {
  case list {
    [] -> None
    _ -> Some(prefix <> list |> string.join(separator) <> suffix)
  }
}

pub fn document_item(
  name: String,
  module_name: String,
  module_interface: pi.Module,
  package_interface: pi.Package,
  print_mode: args.PrintMode,
) -> Result(String, error.Error) {
  let simple =
    simplify_module_interface(module_name, module_interface, package_interface)
  let type_ = dict.get(simple.types, name)
  let value = dict.get(simple.values, name)

  case type_, value {
    Error(_), Error(_) ->
      Error(error.InterfaceError(
        "The module "
        <> module_name
        <> " does not contain an item with the name "
        <> name,
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

/// Generate documentation for an item (type or value)
/// Include representation of the item in addition to the documentation field
/// This is supposed to show as much information as the module page in the html docs
///
fn render_item(item: SimpleItem, module_name: String) -> String {
  "**Documentation for "
  <> item.kind
  <> " `"
  <> item.name
  <> "` in `"
  <> module_name
  <> "`**:\n\n```\n"
  <> item.representation
  <> "\n```"
  <> case item.documentation {
    None | Some("") -> ""
    Some(docs) -> "\n\n" <> docs |> string.trim_right
  }
  <> case item.deprecation {
    None | Some("") -> ""
    Some(deprecation) ->
      "\n\n/!\\ This item has been deprecated:\n" <> deprecation
  }
}

/// Group Types together
type TypeInterface {
  Type(pi.TypeDefinition)
  Alias(pi.TypeAlias)
}

/// Group Values together
type ValueInterface {
  Constant(pi.Constant)
  Function(pi.Function)
  Constructor(cons: pi.TypeConstructor, parent: SimpleItem)
}

/// Represents a simplified Item from the package interface
type SimpleItem {
  SimpleItem(
    name: String,
    kind: String,
    representation: String,
    documentation: Option(String),
    deprecation: Option(String),
  )
}

/// Represents a simplified Module from the package interface
type SimpleModule {
  SimpleModule(
    submodules: List(String),
    types: dict.Dict(String, SimpleItem),
    values: dict.Dict(String, SimpleItem),
  )
}

/// Make a package interface module simpler for our documenting purposes
///
fn simplify_module_interface(
  module_name: String,
  interface: pi.Module,
  package_interface: pi.Package,
) -> SimpleModule {
  let types =
    interface.types
    |> dict.map_values(fn(_, type_) { Type(type_) })
  let types =
    dict.merge(
      types,
      interface.type_aliases
        |> dict.map_values(fn(_, alias) { Alias(alias) }),
    )
    |> dict.map_values(fn(name, type_) {
      simplify_type(name, type_, module_name)
    })

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
              Constructor(
                cons,
                simplify_type(type_name, Type(type_), module_name),
              ),
            )
          })
          |> dict.from_list(),
      )
    })
  let values =
    dict.merge(values, constructors)
    |> dict.map_values(fn(name, value) {
      simplify_value(name, value, module_name)
    })

  let submodules =
    package_interface.modules
    |> dict.keys()
    |> list.filter(string.starts_with(_, module_name <> "/"))

  SimpleModule(types:, values:, submodules:)
}

/// Produces a range of values from start (inclusive) to end (exclusive).
/// Does not support end values less than the start value.
/// 
fn exclusive_range(start: Int, end: Int) -> List(Int) {
  case start >= end {
    True -> []
    False -> list.range(start, end - 1)
  }
}

/// Make a type simpler for our documenting purposes
/// Here we generate the representation for a type
///
fn simplify_type(
  name: String,
  type_: TypeInterface,
  current_module: String,
) -> SimpleItem {
  let documentation = case type_ {
    Type(t) -> t.documentation
    Alias(a) -> a.documentation
  }
  let render_type_parameters = fn(n) {
    list_or_empty(
      "(",
      exclusive_range(0, n)
        |> list.map(get_variable_symbol),
      ", ",
      ")",
    )
  }
  let representation = case type_ {
    Type(t) ->
      "pub type "
      <> name
      <> t.parameters |> render_type_parameters
      <> list_or_empty(
        " {\n  ",
        t.constructors |> list.map(render_constructor(_, current_module)),
        "\n  ",
        "\n}",
      )
    Alias(a) ->
      "type "
      <> name
      <> a.parameters |> render_type_parameters
      <> " = "
      <> render_type(a.alias, current_module)
  }
  let deprecation = case type_ {
    Type(pi.TypeDefinition(deprecation: Some(d), ..)) -> Some(d.message)
    Alias(pi.TypeAlias(deprecation: Some(d), ..)) -> Some(d.message)
    _ -> None
  }
  SimpleItem(name:, kind: "type", documentation:, deprecation:, representation:)
}

/// Make a value simpler for our documenting purposes
/// Here we generate the representation for a type
///
fn simplify_value(
  name: String,
  value: ValueInterface,
  current_module: String,
) -> SimpleItem {
  let documentation = case value {
    Function(f) -> f.documentation
    Constant(c) -> c.documentation
    Constructor(c, _) -> c.documentation
  }
  let representation = case value {
    Function(f) ->
      render_function(name, f.parameters, Some(f.return), current_module)
    Constant(c) ->
      "pub const " <> name <> ": " <> render_type(c.type_, current_module)
    Constructor(c, parent_type) ->
      render_constructor(c, current_module)
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
  SimpleItem(
    name:,
    kind: "value",
    documentation:,
    deprecation:,
    representation:,
  )
}

/// Actually render constructor representation
///
fn render_constructor(c: pi.TypeConstructor, current_module: String) -> String {
  let pi.TypeConstructor(_, name, parameters) = c
  name
  <> list_or_empty(
    "(",
    parameters |> list.map(render_parameter(_, current_module)),
    ", ",
    ")",
  )
}

/// Actually render parameter representation
///
fn render_parameter(p: pi.Parameter, current_module: String) -> String {
  p.label |> option.map(fn(l) { l <> ": " }) |> option.unwrap("")
  <> render_type(p.type_, current_module)
}

/// Actually render function representation
///
fn render_function(
  name: String,
  parameters: List(pi.Parameter),
  return: Option(pi.Type),
  current_module: String,
) -> String {
  let rendered_params = case parameters {
    [] -> "()"
    [param] -> "(" <> render_parameter(param, current_module) <> ")"
    params ->
      "(\n  "
      <> params
      |> list.map(render_parameter(_, current_module))
      |> string.join(", \n  ")
      <> "\n)"
  }
  "pub fn "
  <> name
  <> rendered_params
  <> " -> "
  <> return
  |> option.map(render_type(_, current_module))
  |> option.unwrap("Nil")
}

/// Actually render a type (as in gleam_package_interface.Type) representation
///
fn render_type(type_: pi.Type, current_module: String) -> String {
  case type_ {
    pi.Tuple(elements) ->
      "#("
      <> elements
      |> list.map(render_type(_, current_module))
      |> string.join(", ")
      <> ")"
    pi.Fn(parameters, return) ->
      "fn("
      <> parameters
      |> list.map(render_type(_, current_module))
      |> string.join(", ")
      <> ") -> "
      <> render_type(return, current_module)
    pi.Variable(id) -> get_variable_symbol(id)
    pi.Named(name, _package, module, parameters) -> {
      let qualifier = case module {
        // Don't qualify prelude types
        "gleam" -> ""
        // Don't qualify types in the current module
        _ if module == current_module -> ""
        _ ->
          string.split(module, "/")
          |> list.last
          |> result.unwrap(module)
          <> "."
      }

      qualifier
      <> name
      <> list_or_empty(
        "(",
        parameters |> list.map(render_type(_, current_module)),
        ", ",
        ")",
      )
    }
  }
}

/// Get type variable representation from its ID
/// Based on the anchor definied in the module so that it can be customized
///
fn get_variable_symbol(id: Int) -> String {
  let anchor_code =
    typevar_anchor
    |> string.to_utf_codepoints
    |> list.map(string.utf_codepoint_to_int)
    |> list.first
  anchor_code
  |> result.map(fn(x) { x + id })
  |> result.try(string.utf_codepoint)
  |> result.map(list.wrap)
  |> result.map(string.from_utf_codepoints)
  |> result.unwrap(typevar_anchor)
}
