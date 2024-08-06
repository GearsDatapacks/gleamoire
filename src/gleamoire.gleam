import argv
import gleam/dict
import gleam/http/request
import gleam/httpc
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/package_interface
import gleam/string
import gleamyshell
import glint
import glitzer/spinner
import simplifile
import tom

const default_cache = ".cache/gleamoire"

const hexdocs_url = "https://hexdocs.pm/"

fn type_flag() -> glint.Flag(Bool) {
  glint.bool_flag("t")
  |> glint.flag_default(False)
  |> glint.flag_help("Print the type associated with the given name")
}

fn value_flag() -> glint.Flag(Bool) {
  glint.bool_flag("v")
  |> glint.flag_default(False)
  |> glint.flag_help("Print the value associated with the given name")
}

fn document() -> glint.Command(Nil) {
  use <- glint.command_help("Documents a gleam module, in the command line!")

  use print_type <- glint.flag(type_flag())
  use print_value <- glint.flag(value_flag())

  use _, args, flags <- glint.command()

  let assert Ok(_print_type) = print_type(flags)
  let assert Ok(_print_value) = print_value(flags)

  case args {
    [] ->
      io.println(
        "Please specify a module to document. See gleamoire --help for more information",
      )
    [module, ..] -> io.println(resolve_input(module))
  }
}

fn resolve_input(module_item: String) -> String {
  let #(module_path, item) = case string.split(module_item, on: ".") {
    [module_path, item] -> #(module_path, Some(item))
    [module_path] -> #(module_path, None)
    _ -> panic as "Invalid module item requested"
  }
  let assert [main_module, ..sub] = string.split(module_path, on: "/")

  case main_module {
    "" ->
      panic as "I did not understand what module you are reffering to (should respect main/module.item syntax)"
    _ -> Nil
  }

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
  |> get_docs([main_module, ..sub], item)
}

fn get_package_interface(
  module_name: String,
  module_path: Option(String),
  cache_path: Option(String),
) -> String {
  let assert Ok(home_dir) = gleamyshell.home_directory()
  let cache_location = option.unwrap(cache_path, default_cache)
  let gleamoire_cache = home_dir <> "/" <> cache_location <> "/"

  let package_interface_path =
    gleamoire_cache <> module_name <> "/package-interface.json"

  case simplifile.is_file(package_interface_path), module_path {
    Ok(True), _ -> {
      // If cache file exists
      let assert Ok(body) = simplifile.read(package_interface_path)
      body
    }
    _, Some(dep_path) -> {
      // Build if dep package
      let dep_interface = build_package_interface(dep_path)

      let assert Ok(_) =
        simplifile.create_directory_all(gleamoire_cache <> module_name)
      let assert Ok(_) = simplifile.create_file(package_interface_path)
      let assert Ok(_) = simplifile.write(package_interface_path, dep_interface)

      dep_interface
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

      resp.body
    }
    _, _ -> panic as { "Unable to find " <> module_name <> "'s interface." }
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
) -> String {
  // Get interface string
  let assert Ok(interface) = json.decode(json, using: package_interface.decoder)

  let assert Ok(module_interface) =
    dict.get(interface.modules, string.join(module_path, "/"))

  case item, module_interface.documentation {
    None, [] -> todo as "print out README.md"
    None, module_documentation -> string.join(module_documentation, "\n")
    Some(item), _ -> document_item(module_interface, item)
  }
}

fn document_item(
  module_interface: package_interface.Module,
  name: String,
) -> String {
  let simple = simplify_module_interface(module_interface)
  let type_ = dict.get(simple.types, name)
  let value = dict.get(simple.values, name)
  case type_, value {
    Error(_), Error(_) ->
      panic as { "No item has been found with the name " <> name }
    Ok(type_docs), Error(_) -> type_docs
    Error(_), Ok(value_docs) -> value_docs
    Ok(_), Ok(_) -> todo as "Distinguish types and values with the same name"
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
      interface.constants
        |> dict.map_values(fn(_, constant) {
          constant.documentation |> option.unwrap("")
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
  glint.new()
  |> glint.with_name("gleamoire")
  |> glint.pretty_help(glint.default_pretty_help())
  |> glint.add(at: [], do: document())
  |> glint.run(argv.load().arguments)
}
