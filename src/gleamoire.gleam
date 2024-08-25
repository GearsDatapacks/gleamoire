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
import gleamoire/render.{document_item, document_module}
import gleamyshell
import glitzer/spinner
import simplifile
import tom

const default_cache = ".cache/gleamoire"

const hexdocs_url = "https://hexdocs.pm/"

const gleamoire_version = "1.0.0"

fn document(args: args.Args) -> Result(String, error.Error) {
  case args {
    args.Help -> Ok(args.help_text)
    args.Version -> Ok("Gleamoire v" <> gleamoire_version)
    args.Document(module:, print_mode:, cache_path:, refresh_cache:) ->
      resolve_input(module, print_mode, cache_path, refresh_cache)
  }
}

fn resolve_input(
  module_item: String,
  print_mode: args.PrintMode,
  cache_path: Option(String),
  refresh_cache: Bool,
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
  let sub_is_stdlib = is_stdlib(sub)
  case main_module {
    "gleam" if sub_is_stdlib == True ->
      get_package_interface("gleam_stdlib", None, cache_path, refresh_cache)
    "gleam" ->
      get_package_interface(
        "gleam_" <> result.unwrap(list.first(sub), ""),
        None,
        cache_path,
        refresh_cache,
      )
    "gleam_community" ->
      get_package_interface(
        "gleam_community_" <> result.unwrap(list.first(sub), ""),
        None,
        cache_path,
        refresh_cache,
      )
    module if main_module == current_module ->
      get_package_interface(module, Some("."), cache_path, refresh_cache)
    _ -> {
      use dep <- result.try(
        tom.get_table(config, ["dependencies"])
        |> result.replace_error(error.UnexpectedError(
          "gleam.toml is missing the 'dependencies' key. Please ensure that you have a valid gleam.toml in your project.",
        )),
      )
      let is_dep = dict.has_key(dep, main_module)
      case is_dep {
        True ->
          get_package_interface(
            main_module,
            Some("./build/packages/" <> main_module),
            cache_path,
            refresh_cache,
          )
        False ->
          get_package_interface(main_module, None, cache_path, refresh_cache)
      }
    }
  }
  |> result.try(get_docs(_, [main_module, ..sub], item, print_mode))
}

fn is_stdlib(p: List(String)) -> Bool {
  let stdlib = [
    "bit_array", "bool", "bytes_builder", "dict", "dynamic", "float", "function",
    "int", "io", "iterator", "list", "option", "order", "pair", "queue", "regex",
    "result", "set", "string", "string_builder", "uri",
  ]
  case p {
    [] -> False
    [e, ..] -> list.contains(stdlib, e)
  }
}

fn get_package_interface(
  module_name: String,
  module_path: Option(String),
  cache_path: Option(String),
  refresh_cache: Bool,
) -> Result(String, error.Error) {
  use home_dir <- result.try(
    gleamyshell.home_directory()
    |> result.replace_error(error.UnexpectedError(
      "Could not get the home directory",
    )),
  )
  let cache_location =
    option.unwrap(cache_path, home_dir <> "/" <> default_cache) <> "/"

  let package_interface_path =
    cache_location <> module_name <> "/package-interface.json"

  let cache_exists = simplifile.is_file(package_interface_path)
  use _ <- result.try(case refresh_cache, cache_exists {
    True, Ok(True) -> {
      simplifile.delete(package_interface_path)
      |> result.map_error(fn(error) {
        error.UnexpectedError(
          "Failed to delete cache file: " <> simplifile.describe_error(error),
        )
      })
    }
    _, _ -> Ok(Nil)
  })

  case cache_exists, module_path {
    Ok(True), _ if !refresh_cache -> {
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

      let package_interface_directory = cache_location <> module_name
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
    Ok(_), _ -> {
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

      let cache_directory = cache_location <> module_name
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
      "Failed to decode package-interface.json. Something went wrong during the build process.",
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
      Ok(document_module(joined_path, module_interface, interface))
    Some(item), _ ->
      document_item(item, joined_path, module_interface, interface, print_mode)
  }
}

pub fn main() {
  let result = args.parse(argv.load().arguments) |> result.try(document)

  case result {
    Ok(docs) -> io.println(docs)
    Error(error) -> io.println(error.to_string(error))
  }
}
