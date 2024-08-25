import argv
import gleam/dict
import gleam/http/request
import gleam/httpc
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/package_interface as pi
import gleam/result
import gleam/string
import gleamoire/args
import gleamoire/error
import gleamyshell
import glitzer/spinner
import simplifile
import tom

const default_cache = ".cache/gleamoire"

const hexdocs_url = "https://hexdocs.pm/"

fn document(args: args.Args) -> Result(String, error.Error) {
  case args {
    args.Help -> Ok(args.help_text)
    args.Document(module:, print_mode:, cache_path:) ->
      resolve_input(module, print_mode, cache_path)
  }
}

fn resolve_input(
  module_item: String,
  print_mode: args.PrintMode,
  cache_path: Option(String),
) -> Result(String, error.Error) {
  use #(module_path, item) <- result.try(case
    string.split(module_item, on: ".")
  {
    [module_path, item] -> Ok(#(module_path, Some(item)))
    [module_path] -> Ok(#(module_path, None))
    _ -> Error(error.InputError("Invalid module item requested"))
  })
  // We can safely assert here because string.split will always
  // return at least one string in the list
  let assert [main_module, ..sub] = string.split(module_path, on: "/")

  use _ <- result.try(case main_module {
    "" ->
      Error(error.InputError(
        "I did not understand what module you are referring to (should respect main/module.item syntax)",
      ))
    _ -> Ok(Nil)
  })

  use config_file <- result.try(
    simplifile.read("./gleam.toml")
    |> result.map_error(fn(error) {
      error.UnexpectedError(
        "Could not open gleam.toml: "
        <> simplifile.describe_error(error)
        <> ". Please ensure that gleamoire is run inside a gleam project",
      )
    }),
  )
  use config <- result.try(
    tom.parse(config_file)
    |> result.replace_error(error.UnexpectedError(
      "gleam.toml is malformed. Please ensure that you have a valid gleam.toml in your project",
    )),
  )
  use current_module <- result.try(
    tom.get_string(config, ["name"])
    |> result.replace_error(error.UnexpectedError(
      "gleam.toml is missing the 'name' key. Please ensure that you have a valid gleam.toml in your project",
    )),
  )

  // Retrieve package interface
  case main_module == current_module {
    True -> get_package_interface(current_module, Some("."), cache_path)
    False -> {
      use dep <- result.try(
        tom.get_table(config, ["dependencies"])
        |> result.replace_error(error.UnexpectedError(
          "gleam.toml is missing the 'dependencies' key. Please ensure that you have a valid gleam.toml in your project",
        )),
      )
      let is_dep = dict.has_key(dep, main_module)
      case is_dep {
        True ->
          get_package_interface(
            main_module,
            Some("./build/packages/" <> main_module),
            cache_path,
          )
        False -> get_package_interface(main_module, None, cache_path)
      }
    }
  }
  |> result.try(get_docs(_, [main_module, ..sub], item, print_mode))
}

fn get_package_interface(
  module_name: String,
  module_path: Option(String),
  cache_path: Option(String),
) -> Result(String, error.Error) {
  use home_dir <- result.try(
    gleamyshell.home_directory()
    |> result.replace_error(error.UnexpectedError(
      "Could not get the home directory",
    )),
  )
  let cache_location = option.unwrap(cache_path, default_cache)
  let gleamoire_cache = home_dir <> "/" <> cache_location <> "/"

  let package_interface_path =
    gleamoire_cache <> module_name <> "/package-interface.json"

  case simplifile.is_file(package_interface_path), module_path {
    Ok(True), _ -> {
      // If cache file exists
      simplifile.read(package_interface_path)
      |> result.map_error(fn(error) {
        error.UnexpectedError(
          "Failed to read "
          <> package_interface_path
          <> ": "
          <> simplifile.describe_error(error),
        )
      })
    }
    _, Some(dep_path) -> {
      // Build if dep package
      use dep_interface <- result.try(build_package_interface(dep_path))

      let package_interface_directory = gleamoire_cache <> module_name
      use _ <- result.try(
        simplifile.create_directory_all(package_interface_directory)
        |> result.map_error(fn(error) {
          error.UnexpectedError(
            "Failed to create directory "
            <> package_interface_directory
            <> ": "
            <> simplifile.describe_error(error),
          )
        }),
      )
      use _ <- result.try(
        simplifile.create_file(package_interface_path)
        |> result.map_error(fn(error) {
          error.UnexpectedError(
            "Failed to create file "
            <> package_interface_path
            <> ": "
            <> simplifile.describe_error(error),
          )
        }),
      )
      use _ <- result.map(
        simplifile.write(package_interface_path, dep_interface)
        |> result.map_error(fn(error) {
          error.UnexpectedError(
            "Failed to write to file "
            <> package_interface_path
            <> ": "
            <> simplifile.describe_error(error),
          )
        }),
      )

      dep_interface
    }
    Ok(False), _ -> {
      // If all fails, query hexdocs
      use hex_req <- result.try(
        request.to(hexdocs_url <> module_name <> "/package-interface.json")
        |> result.replace_error(error.UnexpectedError(
          "Failed to construct request url",
        )),
      )

      use resp <- result.try(
        httpc.send(hex_req)
        |> result.map_error(fn(error) {
          error.UnexpectedError(
            "Failed to query " <> hex_req.path <> ": " <> string.inspect(error),
          )
        }),
      )

      // Make sure we don't cache data on 404 or other failed codes
      use _ <- result.try(case resp.status {
        200 -> Ok(Nil)
        _ ->
          Error(error.InterfaceError(
            "Package " <> module_name <> " does not exist.",
          ))
      })

      let cache_directory = gleamoire_cache <> module_name
      use _ <- result.try(
        simplifile.create_directory_all(cache_directory)
        |> result.map_error(fn(error) {
          error.UnexpectedError(
            "Failed to create directory "
            <> cache_directory
            <> ": "
            <> simplifile.describe_error(error),
          )
        }),
      )
      use _ <- result.try(
        simplifile.create_file(package_interface_path)
        |> result.map_error(fn(error) {
          error.UnexpectedError(
            "Failed to create file "
            <> package_interface_path
            <> ": "
            <> simplifile.describe_error(error),
          )
        }),
      )
      use _ <- result.map(
        simplifile.write(package_interface_path, resp.body)
        |> result.map_error(fn(error) {
          error.UnexpectedError(
            "Failed to write to file "
            <> package_interface_path
            <> ": "
            <> simplifile.describe_error(error),
          )
        }),
      )
      resp.body
    }
    _, _ ->
      Error(error.InterfaceError(
        "Unable to find " <> module_name <> "'s interface.",
      ))
  }
}

fn build_package_interface(path: String) -> Result(String, error.Error) {
  let s =
    spinner.spinning_spinner()
    |> spinner.with_right_text(" Building docs")
    |> spinner.spin

  let interface_path = path <> "/package-interface.json"

  case path {
    "." -> {
      let _ =
        gleamyshell.execute("gleam", in: path, args: [
          "export", "package-interface", "--out", "package-interface.json",
        ])
      Nil
    }
    _ -> {
      let _ = gleamyshell.execute("gleam", in: path, args: ["clean"])
      let _ =
        gleamyshell.execute("gleam", in: path, args: [
          "export", "package-interface", "--out", "package-interface.json",
        ])
      let _ = gleamyshell.execute("gleam", in: path, args: ["clean"])
      Nil
    }
  }

  spinner.finish(s)

  simplifile.read(interface_path)
  |> result.map_error(fn(error) {
    error.UnexpectedError(
      "Failed to read "
      <> interface_path
      <> ": "
      <> simplifile.describe_error(error),
    )
  })
}

fn get_docs(
  json: String,
  module_path: List(String),
  item: Option(String),
  print_mode: args.PrintMode,
) -> Result(String, error.Error) {
  // Get interface string
  use interface <- result.try(
    json.decode(json, using: pi.decoder)
    |> result.replace_error(error.UnexpectedError(
      "Failed to decode package-interface.json. Something went wrong with the build process",
    )),
  )

  let joined_path = string.join(module_path, "/")
  use module_interface <- result.try(
    dict.get(interface.modules, joined_path)
    |> result.replace_error(error.InterfaceError(
      "Package " <> interface.name <> " does not contain module " <> joined_path,
    )),
  )

  case item, module_interface.documentation {
    None, _module_documentation ->
      document_module(joined_path, module_interface)
    Some(item), _ ->
      document_item(item, joined_path, module_interface, print_mode)
  }
}

fn document_module(
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

fn document_item(
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
  let doc_skeleton =
    "Documentation for item `"
    <> item.name
    <> "` in `"
    <> module_name
    <> "`:\n\n"
    <> item.representation
  case item.documentation {
    None -> doc_skeleton
    Some(docs) -> doc_skeleton <> "\n\n" <> docs <> "\n"
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

pub fn main() {
  let result = args.parse(argv.load().arguments) |> result.try(document)

  case result {
    Ok(docs) -> io.println(docs)
    Error(error) -> io.println(error.to_string(error))
  }
}
