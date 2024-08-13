import argv
import gleam/dict
import gleam/http/request
import gleam/httpc
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/package_interface
import gleam/result
import gleam/string
import gleamyshell
import glitzer/spinner
import simplifile
import tom

const default_cache = ".cache/gleamoire"

const hexdocs_url = "https://hexdocs.pm/"

type Args {
  Help
  Document(module: String, print_mode: PrintMode)
}

fn parse_args(args: List(String)) -> Result(Args, String) {
  use parsed <- result.try(do_parse_args(
    args,
    Parsed(value_flag: False, type_flag: False, help_flag: False, module: None),
  ))
  use print_mode <- result.try(case parsed.type_flag, parsed.value_flag {
    False, False -> Ok(Unspecified)
    True, False -> Ok(Type)
    False, True -> Ok(Value)
    True, True -> Error("Only one of -t and -v may be specified")
  })
  case parsed {
    Parsed(help_flag: True, ..) -> Ok(Help)
    Parsed(module: Some(module), ..) -> Ok(Document(module, print_mode))
    Parsed(module: None, help_flag: False, ..) ->
      Error(
        "Please specify a module to document. See gleamoire --help for more information",
      )
  }
}

type Parsed {
  Parsed(
    value_flag: Bool,
    type_flag: Bool,
    help_flag: Bool,
    module: Option(String),
  )
}

fn do_parse_args(args: List(String), parsed: Parsed) -> Result(Parsed, String) {
  case args {
    [] -> Ok(parsed)
    [arg, ..args] -> {
      use parsed <- result.try(case arg {
        "-t" ->
          case parsed.type_flag {
            True -> Error("Flags can only be specified once")
            False -> Ok(Parsed(..parsed, type_flag: True))
          }
        "-v" ->
          case parsed.value_flag {
            True -> Error("Flags can only be specified once")
            False -> Ok(Parsed(..parsed, value_flag: True))
          }
        "--help" | "-h" ->
          case parsed.help_flag {
            True -> Error("Flags can only be specified once")
            False -> Ok(Parsed(..parsed, help_flag: True))
          }
        _ ->
          case parsed.module {
            Some(_) -> Error("Please only specify one module to document")
            None -> Ok(Parsed(..parsed, module: Some(arg)))
          }
      })
      do_parse_args(args, parsed)
    }
  }
}

type PrintMode {
  Unspecified
  Type
  Value
}

const help_text = "Documents a gleam module, type or value, in the command line!

Usage:
gleamoire <module> [flags]

Flags:
--help, -h   Print this help text
-t           Print the type associated with the given name
-v           Print the value associated with the given name"

fn document(args: Args) -> Result(String, String) {
  case args {
    Help -> Ok(help_text)
    Document(module:, print_mode:) -> resolve_input(module, print_mode)
  }
}

fn resolve_input(
  module_item: String,
  print_mode: PrintMode,
) -> Result(String, String) {
  use #(module_path, item) <- result.try(case
    string.split(module_item, on: ".")
  {
    [module_path, item] -> Ok(#(module_path, Some(item)))
    [module_path] -> Ok(#(module_path, None))
    _ -> Error("Invalid module item requested")
  })
  let assert [main_module, ..sub] = string.split(module_path, on: "/")

  use _ <- result.try(case main_module {
    "" ->
      Error(
        "I did not understand what module you are reffering to (should respect main/module.item syntax)",
      )
    _ -> Ok(Nil)
  })

  let assert Ok(config_file) = simplifile.read("./gleam.toml")
  let assert Ok(config) = tom.parse(config_file)
  let assert Ok(current_module) = tom.get_string(config, ["name"])

  // Retrieve package interface
  case main_module == current_module {
    True -> get_package_interface(current_module, Some("."), None)
    False -> {
      let assert Ok(dep) = tom.get_table(config, ["dependencies"])
      let is_dep = dict.has_key(dep, main_module)
      case is_dep {
        True ->
          get_package_interface(
            main_module,
            Some("./build/packages/" <> main_module),
            None,
          )
        False -> get_package_interface(main_module, None, None)
      }
    }
  }
  |> result.try(get_docs(_, [main_module, ..sub], item, print_mode))
}

fn get_package_interface(
  module_name: String,
  module_path: Option(String),
  cache_path: Option(String),
) -> Result(String, String) {
  let assert Ok(home_dir) = gleamyshell.home_directory()
  let cache_location = option.unwrap(cache_path, default_cache)
  let gleamoire_cache = home_dir <> "/" <> cache_location <> "/"

  let package_interface_path =
    gleamoire_cache <> module_name <> "/package-interface.json"

  case simplifile.is_file(package_interface_path), module_path {
    Ok(True), _ -> {
      // If cache file exists
      let assert Ok(body) = simplifile.read(package_interface_path)
      Ok(body)
    }
    _, Some(dep_path) -> {
      // Build if dep package
      let dep_interface = build_package_interface(dep_path)

      let assert Ok(_) =
        simplifile.create_directory_all(gleamoire_cache <> module_name)
      let assert Ok(_) = simplifile.create_file(package_interface_path)
      let assert Ok(_) = simplifile.write(package_interface_path, dep_interface)

      Ok(dep_interface)
    }
    Ok(False), _ -> {
      // If all fails, query hexdocs
      let assert Ok(hex_req) =
        request.to(hexdocs_url <> module_name <> "/package-interface.json")

      let assert Ok(resp) = httpc.send(hex_req)
      let assert Ok(_) =
        simplifile.create_directory_all(gleamoire_cache <> module_name)
      let assert Ok(_) = simplifile.create_file(package_interface_path)
      let assert Ok(_) = simplifile.write(package_interface_path, resp.body)

      Ok(resp.body)
    }
    _, _ -> Error({ "Unable to find " <> module_name <> "'s interface." })
  }
}

fn build_package_interface(path: String) -> String {
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

  let assert Ok(interface) = simplifile.read(interface_path)
  interface
}

fn get_docs(
  json: String,
  module_path: List(String),
  item: Option(String),
  print_mode: PrintMode,
) -> Result(String, String) {
  // Get interface string
  let assert Ok(interface) = json.decode(json, using: package_interface.decoder)

  let assert Ok(module_interface) =
    dict.get(interface.modules, string.join(module_path, "/"))

  case item, module_interface.documentation {
    None, [] -> todo as "print out README.md"
    None, module_documentation -> Ok(string.join(module_documentation, "\n"))
    Some(item), _ -> document_item(module_interface, item, print_mode)
  }
}

fn document_item(
  module_interface: package_interface.Module,
  name: String,
  print_mode: PrintMode,
) -> Result(String, String) {
  let simple = simplify_module_interface(module_interface)
  let type_ = dict.get(simple.types, name)
  let value = dict.get(simple.values, name)
  case type_, value {
    Error(_), Error(_) -> Error("No item has been found with the name " <> name)
    Ok(type_docs), Error(_) -> Ok(type_docs)
    Error(_), Ok(value_docs) -> Ok(value_docs)
    Ok(type_docs), Ok(value_docs) ->
      case print_mode {
        Unspecified ->
          Error(
            "There is both a type and value with that name. Please specify -t or -v to print the one you want",
          )
        Type -> Ok(type_docs)
        Value -> Ok(value_docs)
      }
  }
}

type SimpleModule {
  SimpleModule(
    types: dict.Dict(String, String),
    values: dict.Dict(String, String),
  )
}

fn simplify_module_interface(interface: package_interface.Module) {
  let types =
    interface.types
    |> dict.map_values(fn(_, type_) { type_.documentation |> option.unwrap("") })
  let types =
    dict.merge(
      types,
      interface.type_aliases
        |> dict.map_values(fn(_, alias) {
          alias.documentation |> option.unwrap("")
        }),
    )

  let values =
    interface.constants
    |> dict.map_values(fn(_, constant) {
      constant.documentation |> option.unwrap("")
    })
  let values =
    dict.merge(
      values,
      interface.functions
        |> dict.map_values(fn(_, function) {
          function.documentation |> option.unwrap("")
        }),
    )
  let constructors =
    list.fold(dict.values(interface.types), dict.new(), fn(acc, type_) {
      dict.merge(
        acc,
        type_.constructors
          |> list.map(fn(cons) {
            #(cons.name, cons.documentation |> option.unwrap(""))
          })
          |> dict.from_list(),
      )
    })
  let values = dict.merge(values, constructors)
  SimpleModule(types:, values:)
}

pub fn main() {
  let result = parse_args(argv.load().arguments) |> result.try(document)

  case result {
    Ok(docs) -> io.println(docs)
    Error(error) -> io.println(error)
  }
}
