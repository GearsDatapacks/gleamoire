import gleam/option.{type Option, None, Some}
import gleam/result
import gleamoire/error

pub type Args {
  Help
  Version
  Document(
    query: String,
    print_mode: PrintMode,
    cache_path: Option(String),
    refresh_cache: Bool,
  )
}

pub type PrintMode {
  Unspecified
  Type
  Value
}

pub const help_text = "A handy grimoire for gleam packages !
Documents a gleam module, type or value, in the command line!

Usage:
gleamoire <query> [flags]

Flags:
--help, -h     Print this help text
--version      Print the currently installed version of Gleamoire
--type, -t     Print the type associated with the given name
--value, -v    Print the value associated with the given name
--cache, -C    Use a different cache location for package-interface.json
--refresh, -r  Refresh the cache for the documented module, in case it is outdataded"

pub fn parse(args: List(String)) -> Result(Args, error.Error) {
  use parsed <- result.try(do_parse_args(
    args,
    Parsed(
      value_flag: False,
      type_flag: False,
      help_flag: False,
      version_flag: False,
      refresh_cache: False,
      query: None,
      cache_path: None,
    ),
  ))
  use print_mode <- result.try(case parsed.type_flag, parsed.value_flag {
    False, False -> Ok(Unspecified)
    True, False -> Ok(Type)
    False, True -> Ok(Value)
    True, True ->
      Error(error.InputError("Only one of -t and -v may be specified"))
  })
  case parsed {
    Parsed(help_flag: True, ..) -> Ok(Help)
    Parsed(version_flag: True, ..) -> Ok(Version)
    Parsed(query: Some(query), cache_path:, refresh_cache:, ..) ->
      Ok(Document(query:, print_mode:, cache_path:, refresh_cache:))
    // Special case for `gleamoire -v`, in case the user was trying to specify --version
    Parsed(query: None, value_flag: True, ..) ->
      Error(error.InputError(
        "The -v flag must be used in combination with a module to document. "
        <> "If you meant to print the current version, use --version instead. "
        <> "See gleamoire --help for more information.",
      ))
    Parsed(query: None, ..) ->
      Error(error.InputError(
        "Please specify a module to document. See gleamoire --help for more information",
      ))
  }
}

type Parsed {
  Parsed(
    value_flag: Bool,
    type_flag: Bool,
    version_flag: Bool,
    help_flag: Bool,
    refresh_cache: Bool,
    cache_path: Option(String),
    query: Option(String),
  )
}

fn do_parse_args(
  args: List(String),
  parsed: Parsed,
) -> Result(Parsed, error.Error) {
  case args {
    [] -> Ok(parsed)
    ["--cache"] | ["-C"] -> Error(error.InputError("No cache path provided"))
    ["--cache", cache_path, ..args] | ["-C", cache_path, ..args] ->
      case parsed.cache_path {
        None ->
          do_parse_args(args, Parsed(..parsed, cache_path: Some(cache_path)))
        Some(_) ->
          Error(error.InputError(
            "Custom cache location should only be specified once",
          ))
      }
    [arg, ..args] -> {
      case arg {
        "--type" | "-t" ->
          case parsed.type_flag {
            True -> Error(error.InputError("Flags can only be specified once"))
            False -> Ok(Parsed(..parsed, type_flag: True))
          }
        "--value" | "-v" ->
          case parsed.value_flag {
            True -> Error(error.InputError("Flags can only be specified once"))
            False -> Ok(Parsed(..parsed, value_flag: True))
          }
        "--help" | "-h" ->
          case parsed.help_flag {
            True -> Error(error.InputError("Flags can only be specified once"))
            False -> Ok(Parsed(..parsed, help_flag: True))
          }
        "--version" ->
          case parsed.version_flag {
            True -> Error(error.InputError("Flags can only be specified once"))
            False -> Ok(Parsed(..parsed, version_flag: True))
          }
        "--refresh" | "-r" ->
          case parsed.help_flag {
            True -> Error(error.InputError("Flags can only be specified once"))
            False -> Ok(Parsed(..parsed, refresh_cache: True))
          }
        _ ->
          case parsed.query {
            Some(_) ->
              Error(error.InputError("Please only specify one name to document"))
            None -> Ok(Parsed(..parsed, query: Some(arg)))
          }
      }
      |> result.try(do_parse_args(args, _))
    }
  }
}
