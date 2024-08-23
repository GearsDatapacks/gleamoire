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
    args.Document(module:, print_mode:) -> resolve_input(module, print_mode)
  }
}

fn resolve_input(
  module_item: String,
  print_mode: args.PrintMode,
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
    True -> get_package_interface(current_module, Some("."), None)
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
    json.decode(json, using: package_interface.decoder)
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
    Some(item), _ -> document_item(module_interface, item, print_mode)
  }
}

fn document_module(
  module_name: String,
  module_interface: package_interface.Module,
) -> Result(String, error.Error) {
  let simple = simplify_module_interface(module_interface)
  let available_modules =
    "## Available items in "
    <> module_name
    <> "\n\n"
    <> "### Types\n"
    <> string.join(
      list.map(dict.keys(simple.types), string.append("  - ", _)),
      "\n",
    )
    <> "\n\n"
    <> "### Values\n"
    <> string.join(
      list.map(dict.keys(simple.values), string.append("  - ", _)),
      "\n",
    )
  let module_documentation = case module_interface.documentation {
    [] -> ""
    // TODO: https://trello.com/c/qXFKt5Q7  Might open README.md if toplevel documentation
    doc ->
      "\n\n## Documentation for `"
      <> module_name
      <> "`\n"
      <> string.join(doc, "\n")
  }

  Ok(available_modules <> module_documentation)
}

fn document_item(
  module_interface: package_interface.Module,
  name: String,
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
  let result = args.parse(argv.load().arguments) |> result.try(document)

  case result {
    Ok(docs) -> io.println(docs)
    Error(error) -> io.println(error.to_string(error))
  }
}
