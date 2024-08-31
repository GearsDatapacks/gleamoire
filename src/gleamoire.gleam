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

/// Default location for cached package interfaces
///
const default_cache = ".cache/gleamoire"

/// Default Hexdocs URL
///
const hexdocs_url = "https://hexdocs.pm/"

const gleamoire_version = "1.0.0"

/// Transforms command line arguments into appropriate output
///
fn document(args: args.Args) -> Result(String, error.Error) {
  case args {
    args.Help -> Ok(args.help_text)
    args.Version -> Ok("Gleamoire v" <> gleamoire_version)
    args.Document(query:, print_mode:, cache_path:, refresh_cache:) -> {
      use name <- result.try(parse_query(query))
      use interface <- result.try(package_interface(
        name,
        cache_path,
        refresh_cache,
      ))
      let assert ParsedQuery(_, [main_module, ..sub], item) = name
      use docs <- result.try(get_docs(
        interface,
        [main_module, ..sub],
        item,
        print_mode,
      ))
      Ok(docs)
    }
  }
}

/// Holds parsed values from user query
///
pub type ParsedQuery {
  ParsedQuery(
    package: Option(String),
    module_path: List(String),
    item: Option(String),
  )
}

/// Turns an arbitrary string into a parsed query
/// The expected input looks like this : [package:]module/name[.item]
/// Parts between brackets can be ommited
///
pub fn parse_query(query: String) -> Result(ParsedQuery, error.Error) {
  use #(package, module_item) <- result.try(case string.split(query, on: ":") {
    [module_item] -> Ok(#(None, module_item))
    ["", _] ->
      Error(error.InputError(
        "No package name found. Try specifying one in your query, for example : `wibble:wobble/mod.item`",
      ))
    [package, module_item] -> Ok(#(Some(package), module_item))
    _ -> Error(error.InputError("Invalid package item query."))
  })
  use #(module_path, item) <- result.try(case
    string.split(module_item, on: ".")
  {
    [_, ""] -> Error(error.InputError("No item provided"))
    [module_path] -> Ok(#(module_path, None))
    [module_path, item] -> Ok(#(module_path, Some(item)))
    _ -> Error(error.InputError("Invalid module item requested"))
  })
  // We can safely assert here because string.split will always
  // return at least one string in the list
  let assert [main_module, ..sub] = string.split(module_path, on: "/")

  use _ <- result.try(case main_module {
    "" ->
      Error(error.InputError(
        "I did not understand what module you are referring to (should respect [package:]main/module.item syntax)",
      ))
    _ -> Ok(Nil)
  })

  Ok(ParsedQuery(package, [main_module, ..sub], item))
}

/// Main package interface resolution entrypoint
/// This is where we handle shorthands for gleam packages and edge cases
///
fn package_interface(
  query: ParsedQuery,
  cache_path: Option(String),
  refresh_cache: Bool,
) -> Result(String, error.Error) {
  let assert ParsedQuery(package, [main_module, ..sub], _item) = query

  // Retrieve package interface
  let sub_is_stdlib = is_stdlib(sub)
  case package, main_module {
    Some(package), _ -> package
    None, "gleam" if sub_is_stdlib == True -> "gleam_stdlib"
    None, "gleam" -> "gleam_" <> result.unwrap(list.first(sub), "")
    None, "gleam_community" ->
      "gleam_community_" <> result.unwrap(list.first(sub), "")
    None, module -> module
  }
  |> build_or_cache_interface(cache_path, refresh_cache)
}

/// Returns whether p is part of the standard library
///
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

/// Handle cache package interface logic
/// Here we decide to read from cache, refresh cache or initialize it
///
fn build_or_cache_interface(
  package: String,
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
    option.unwrap(cache_path, home_dir <> "/" <> default_cache)
    <> "/"
    <> package

  let interface_path = cache_location <> "/package-interface.json"

  let cache_exists = simplifile.is_file(interface_path)
  case refresh_cache, cache_exists {
    True, Ok(True) -> {
      // Refresh cache
      use _ <- result.try(
        simplifile.delete(interface_path)
        |> result.map_error(fn(error) {
          error.UnexpectedError(
            "Failed to delete cache file: " <> simplifile.describe_error(error),
          )
        }),
      )
      get_interface(package)
      |> result.try(write_file(_, cache_location, "package-interface.json"))
    }
    False, Ok(True) -> {
      // Get cache
      simplifile.read(interface_path)
      |> result.map_error(fn(error) {
        error.FileError(
          "Failed to read "
          <> interface_path
          <> ": "
          <> simplifile.describe_error(error),
        )
      })
    }
    _, _ -> {
      // Init cache
      get_interface(package)
      |> result.try(write_file(_, cache_location, "package-interface.json"))
    }
  }
}

/// Decide to build cache from source or pull cache from Hex
///
fn get_interface(package: String) -> Result(String, error.Error) {
  case simplifile.is_file("./gleam.toml") {
    Ok(True) -> {
      let assert Ok(config_file) = simplifile.read("./gleam.toml")
      use config <- result.try(
        tom.parse(config_file)
        |> result.replace_error(error.UnexpectedError(
          "gleam.toml is malformed. Please ensure that you have a valid gleam.toml in your project",
        )),
      )
      use dep <- result.try(
        tom.get_table(config, ["dependencies"])
        |> result.replace_error(error.UnexpectedError(
          "gleam.toml is missing the 'dependencies' key. Please ensure that you have a valid gleam.toml in your project.",
        )),
      )
      use current_package <- result.try(
        tom.get_string(config, ["name"])
        |> result.replace_error(error.UnexpectedError(
          "gleam.toml is missing the 'name' key. Please ensure that you have a valid gleam.toml in your project",
        )),
      )

      case package == current_package, dict.has_key(dep, package) {
        True, _ -> build_package_interface(".")
        False, True -> build_package_interface("./build/packages/" <> package)
        _, _ -> get_remote_interface(package)
      }
    }
    Ok(False) | Error(_) -> get_remote_interface(package)
  }
  |> result.replace_error(error.InterfaceError(
    "Unable to find " <> package <> "'s interface.
        If you are documenting a module inside a package with a different name,
        try specifying the package name explicitly : `package:module/wibble.item`",
  ))
}

/// Actually build package interface from source
///
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

  let interface =
    simplifile.read(interface_path)
    |> result.map_error(fn(error) {
      error.FileError(
        "Failed to read "
        <> interface_path
        <> ": "
        <> simplifile.describe_error(error),
      )
    })

  let _ =
    simplifile.delete(interface_path)
    |> result.map_error(fn(error) {
      error.FileError(
        "Failed to cleanup built "
        <> interface_path
        <> ": "
        <> simplifile.describe_error(error),
      )
    })

  spinner.finish(s)

  interface
}

/// Pull docs from Hex
///
fn get_remote_interface(package: String) -> Result(String, error.Error) {
  let s =
    spinner.spinning_spinner()
    |> spinner.with_right_text(" Pulling docs from Hex")
    |> spinner.spin

  use hex_req <- result.try(
    request.to(hexdocs_url <> package <> "/package-interface.json")
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

  spinner.finish(s)

  // Make sure we don't cache data on 404 or other failed codes
  use _ <- result.try(case resp.status {
    200 -> Ok(Nil)
    _ ->
      Error(error.InterfaceError("Package " <> package <> " does not exist."))
  })

  Ok(resp.body)
}

/// Write string contents to file at provided location
///
fn write_file(
  content: String,
  path: String,
  filename: String,
) -> Result(String, error.Error) {
  let file_path = path <> "/" <> filename
  use _ <- result.try(
    simplifile.create_directory_all(path)
    |> result.map_error(fn(error) {
      error.FileError(
        "Failed to create directory "
        <> path
        <> ": "
        <> simplifile.describe_error(error),
      )
    }),
  )
  use _ <- result.try(
    simplifile.create_file(file_path)
    |> result.map_error(fn(error) {
      error.FileError(
        "Failed to create file "
        <> file_path
        <> ": "
        <> simplifile.describe_error(error),
      )
    }),
  )
  use _ <- result.map(
    simplifile.write(file_path, content)
    |> result.map_error(fn(error) {
      error.FileError(
        "Failed to write to file "
        <> file_path
        <> ": "
        <> simplifile.describe_error(error),
      )
    }),
  )
  content
}

/// Main entrypoint for docs retrival
///
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
      "Package "
      <> interface.name
      <> " does not contain module "
      <> joined_path
      <> ".\nAvailable modules: \n"
      <> dict.keys(interface.modules)
      |> list.map(string.append("  - ", _))
      |> string.join("\n"),
    )),
  )

  case item {
    Some(item) ->
      document_item(item, joined_path, module_interface, interface, print_mode)
    None -> Ok(document_module(joined_path, module_interface, interface))
  }
}

/// Entrypoint to gleamoire
///
pub fn main() {
  let result = argv.load().arguments |> args.parse |> result.try(document)

  case result {
    Ok(docs) -> docs |> string.trim_right |> io.println
    Error(error) -> io.println(error.to_string(error))
  }
}
