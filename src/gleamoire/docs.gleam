import gleam/dict
import gleam/http/request
import gleam/httpc
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/package_interface as pi
import gleam/result
import gleam/string
import gleamoire/args
import gleamoire/error
import gleamoire/prelude
import gleamoire/render.{document_item, document_module}
import gleamoire/version.{type ResolvedVersion, type Version}
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

/// Main entrypoint for docs retrival
///
pub fn get_docs(
  interface: pi.Package,
  module_path: List(String),
  item: Option(String),
  print_mode: args.PrintMode,
) -> Result(String, error.Error) {
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

/// Resolve the version of a package by checking if it's a dependency,
/// or if it exists in the cache. Returns None if we both of those fail
/// and the user didn't specify one, to avoid querying hexdocs more than once.
/// 
fn resolve_version(
  package: String,
  cache_path: String,
  version: Option(Version),
  refresh_cache: Bool,
) -> ResolvedVersion {
  // If the user specified the version, we return it immediately
  use <- option.lazy_unwrap(version |> option.map(version.Specified))

  // Check if the package is the current package
  use <- result.lazy_unwrap({
    use config_file <- result.try(
      simplifile.read("./gleam.toml") |> result.replace_error(Nil),
    )
    use config <- result.try(
      tom.parse(config_file)
      |> result.replace_error(Nil),
    )

    use current_package <- result.try(
      tom.get_string(config, ["name"])
      |> result.replace_error(Nil),
    )

    case package == current_package {
      False -> Error(Nil)
      True -> {
        use version <- result.try(
          tom.get_string(config, ["version"]) |> result.replace_error(Nil),
        )
        version.parse(version)
        |> result.replace_error(Nil)
        |> result.map(version.Resolved)
      }
    }
  })

  // Check for dependencies
  use <- result.lazy_unwrap({
    use file <- result.try(
      simplifile.read("./manifest.toml") |> result.replace_error(Nil),
    )
    use manifest <- result.try(tom.parse(file) |> result.replace_error(Nil))
    use packages <- result.try(
      tom.get_array(manifest, ["packages"]) |> result.replace_error(Nil),
    )
    packages
    |> list.find_map(fn(toml) {
      case toml {
        tom.InlineTable(dict) ->
          case dict.get(dict, "name"), dict.get(dict, "version") {
            Ok(tom.String(p)), Ok(tom.String(v)) if p == package ->
              version.parse(v) |> result.replace_error(Nil)
            _, _ -> Error(Nil)
          }
        _ -> Error(Nil)
      }
    })
    |> result.map(version.Resolved)
  })

  case simplifile.read_directory(cache_path) {
    Ok(versions) if versions != [] && !refresh_cache -> {
      // If we have a cache for this package, default to the highest cached version
      versions
      |> list.filter_map(version.parse)
      |> version.max_of
      |> result.map(version.Resolved)
      |> result.unwrap(version.Unresolved)
    }
    _ -> version.Unresolved
  }
}

/// Main package interface resolution entrypoint
/// This is where we handle shorthands for gleam packages and edge cases
///
pub fn package_interface(
  query: args.ParsedQuery,
  cache_path: Option(String),
  version: Option(Version),
  refresh_cache: Bool,
) -> Result(pi.Package, error.Error) {
  let assert args.ParsedQuery(package, [main_module, ..sub], _item) = query

  case package, main_module, sub {
    // Special case for gleam prelude
    None, "gleam", [] -> Ok(prelude.prelude_interface())
    _, _, _ -> {
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
      |> get_cached_interface(cache_path, version, refresh_cache)
    }
  }
}

/// Parse a JSON string into a package_interface.Package
///
pub fn parse_interface(json: String) -> Result(pi.Package, error.Error) {
  json.decode(json, using: pi.decoder)
  |> result.replace_error(error.UnexpectedError(
    "Failed to decode package-interface.json. Something went wrong during the build process.",
  ))
}

/// Returns whether p is part of the standard library
///
fn is_stdlib(p: List(String)) -> Bool {
  let stdlib = [
    "bit_array", "bool", "bytes_builder", "bytes_tree", "dict", "dynamic",
    "float", "function", "int", "io", "iterator", "list", "option", "order",
    "pair", "queue", "regex", "result", "set", "string", "string_builder",
    "string_tree", "uri",
  ]
  case p {
    [] -> False
    [e, ..] -> list.contains(stdlib, e)
  }
}

/// Handle cache package interface logic
/// Here we decide to read from cache, refresh cache or initialize it
///
fn get_cached_interface(
  package: String,
  cache_path: Option(String),
  version: Option(Version),
  refresh_cache: Bool,
) -> Result(pi.Package, error.Error) {
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

  case resolve_version(package, cache_location, version, refresh_cache) {
    // This means we have no cache for the package and need to resolve the version
    // from hexdocs. This requires parsing the interface, so we may as well only do it once.
    version.Unresolved as v -> {
      use interface <- result.try(get_interface(package, v))
      use parsed <- result.try(parse_interface(interface))

      write_file(
        interface,
        cache_location <> "/" <> parsed.version,
        "package-interface.json",
      )
      |> result.replace(parsed)
    }
    version.Resolved(v) as version | version.Specified(v) as version -> {
      let cache_location = cache_location <> "/" <> v |> version.to_string

      let interface_path = cache_location <> "/package-interface.json"

      let cache_exists = simplifile.is_file(interface_path)
      case refresh_cache, cache_exists {
        True, Ok(True) -> {
          // Refresh cache
          use _ <- result.try(
            simplifile.delete(interface_path)
            |> result.map_error(fn(error) {
              error.FileError(file: interface_path, action: "delete", error:)
            }),
          )
          get_interface(package, version)
          |> result.try(write_file(_, cache_location, "package-interface.json"))
        }
        False, Ok(True) -> {
          // Get cache
          simplifile.read(interface_path)
          |> result.map_error(fn(error) {
            error.FileError(file: interface_path, action: "read", error:)
          })
        }
        _, _ -> {
          // Init cache
          get_interface(package, version)
          |> result.try(write_file(_, cache_location, "package-interface.json"))
        }
      }
      |> result.try(parse_interface)
    }
  }
}

/// Decide to build interface from source or pull it from Hex
///
fn get_interface(
  package: String,
  version: ResolvedVersion,
) -> Result(String, error.Error) {
  case simplifile.read("./gleam.toml") {
    Ok(config_file) -> {
      use config <- result.try(
        tom.parse(config_file)
        |> result.replace_error(error.UnexpectedError(
          "gleam.toml is malformed. Please ensure that you have a valid gleam.toml in your project",
        )),
      )
      // The `dependencies` key is optional, so if it is not present we pull from hex
      case tom.get_table(config, ["dependencies"]) {
        Ok(dependencies) -> {
          use current_package <- result.try(
            tom.get_string(config, ["name"])
            |> result.replace_error(error.UnexpectedError(
              "gleam.toml is missing the 'name' key. Please ensure that you have a valid gleam.toml in your project",
            )),
          )

          case
            package == current_package,
            dict.has_key(dependencies, package),
            version
          {
            // If the user specified the version, we don't build the docs locally.
            // In future, we could check if the local copy matches the version that
            // the user specified, but in most cases that won't be the case, and it
            // requires extra work, so for now we just pull from hex in that case.
            True, _, version.Resolved(_) -> build_package_interface(".")
            False, True, version.Resolved(_) ->
              build_package_interface("./build/packages/" <> package)
            _, _, _ ->
              get_remote_interface(package, version |> version.to_option)
          }
        }
        Error(_) -> {
          get_remote_interface(package, version |> version.to_option)
        }
      }
    }
    Error(_) -> get_remote_interface(package, version |> version.to_option)
  }
}

/// Actually build package interface from source
///
fn build_package_interface(path: String) -> Result(String, error.Error) {
  let s =
    spinner.spinning_spinner()
    |> spinner.with_right_text(" Building docs")
    |> spinner.spin

  let interface_path = path <> "/package-interface.json"

  // TODO: In the future it would be good not to have to run `gleam clean`.
  // Right now it is needed: https://github.com/gleam-lang/gleam/issues/2898
  let _ = gleamyshell.execute("gleam", in: path, args: ["clean"])
  let _ =
    gleamyshell.execute("gleam", in: path, args: [
      "export", "package-interface", "--out", "package-interface.json",
    ])

  case path {
    "." -> Nil
    // Clean up build directory for dependencies
    _ -> {
      let _ = gleamyshell.execute("gleam", in: path, args: ["clean"])
      Nil
    }
  }

  let interface =
    simplifile.read(interface_path)
    |> result.map_error(fn(error) {
      error.FileError(file: interface_path, action: "read", error:)
    })

  let _ =
    simplifile.delete(interface_path)
    |> result.map_error(fn(error) {
      error.FileError(file: interface_path, action: "cleanup built", error:)
    })

  spinner.finish(s)

  interface
  |> result.replace_error(error.BuildError(
    "Unable to build interface at location " <> path,
  ))
}

/// Pull docs from Hex
///
pub fn get_remote_interface(
  package: String,
  version: Option(Version),
) -> Result(String, error.Error) {
  let s =
    spinner.spinning_spinner()
    |> spinner.with_right_text(" Pulling docs from Hex")
    |> spinner.spin

  let version_string = case version {
    Some(v) -> "/" <> version.to_string(v)
    // If no version could be resolved, default to the latest
    None -> ""
  }

  use hex_req <- result.try(
    request.to(
      hexdocs_url <> package <> version_string <> "/package-interface.json",
    )
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
  case resp.status {
    200 -> Ok(resp.body)
    _ -> {
      let main_message = case version {
        Some(v) ->
          "Package "
          <> package
          <> " does not exist, or does not have a version "
          <> version.to_string(v)
          <> "."
        None -> "Package " <> package <> " does not exist."
      }

      Error(error.InterfaceError(
        main_message
        <> "\n\n"
        <> "If you are documenting a module inside a package with a different name,
try specifying the package name explicitly: `package:module/wibble.item`

If the package does exist, but was published before Gleam v1.0.0, it will not
contain a package-interface.json file and cannot be documented.",
      ))
    }
  }
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
      error.FileError(file: path, action: "create directory", error:)
    }),
  )
  use _ <- result.try(
    simplifile.create_file(file_path)
    |> result.map_error(fn(error) {
      error.FileError(file: file_path, action: "create", error:)
    }),
  )

  simplifile.write(file_path, content)
  |> result.map_error(fn(error) {
    error.FileError(action: "write to", file: file_path, error:)
  })
  |> result.replace(content)
}
