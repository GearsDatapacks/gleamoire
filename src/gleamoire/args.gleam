import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleamoire/error

pub type Args {
  Help
  Version
  Document(
    query: ParsedQuery,
    print_mode: PrintMode,
    cache_path: Option(String),
    refresh_cache: Bool,
    print_raw: Bool,
  )
}

pub type PrintMode {
  Unspecified
  Type
  Value
}

pub const help_text = "A handy grimoire for gleam packages!
Documents a gleam module, type or value, in the command line!

Usage:
gleamoire <query> [flags]

Flags:
--help, -h     Print this help text
--version      Print the currently installed version of Gleamoire
--type, -t     Print the type associated with the given name
--value, -v    Print the value associated with the given name
--cache, -C    Use a different cache location for package-interface.json
--refresh, -r  Refresh the cache for the documented module, in case it is outdataded
--raw          Prints raw text of documentation, without rendering markdown"

/// Parse a list of strings into structured arguments
///
pub fn parse_args(args: List(String)) -> Result(Args, error.Error) {
  use parsed <- result.try(do_parse_args(
    args,
    ParsedArgs(
      value_flag: False,
      type_flag: False,
      help_flag: False,
      version_flag: False,
      refresh_cache: False,
      print_raw: False,
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
    ParsedArgs(help_flag: True, ..) -> Ok(Help)
    ParsedArgs(version_flag: True, ..) -> Ok(Version)
    ParsedArgs(query: Some(query), cache_path:, refresh_cache:, print_raw:, ..) -> {
      use parsed_query <- result.try(parse_query(query))
      Ok(Document(
        query: parsed_query,
        print_mode:,
        cache_path:,
        refresh_cache:,
        print_raw:,
      ))
    }
    // Special case for `gleamoire -v`, in case the user was trying to specify --version
    ParsedArgs(query: None, value_flag: True, ..) ->
      Error(error.InputError(
        "The -v flag must be used in combination with a module to document. "
        <> "If you meant to print the current version, use --version instead. "
        <> "See gleamoire --help for more information.",
      ))
    ParsedArgs(query: None, ..) ->
      Error(error.InputError(
        "Please specify a module to document. See gleamoire --help for more information",
      ))
  }
}

/// Represent current state of argument parsing
///
type ParsedArgs {
  ParsedArgs(
    value_flag: Bool,
    type_flag: Bool,
    version_flag: Bool,
    help_flag: Bool,
    refresh_cache: Bool,
    print_raw: Bool,
    cache_path: Option(String),
    query: Option(String),
  )
}

/// Actually parse input from command line in a fold-like fashion
///
fn do_parse_args(
  args: List(String),
  parsed: ParsedArgs,
) -> Result(ParsedArgs, error.Error) {
  case args {
    [] -> Ok(parsed)
    ["--cache"] | ["-C"] -> Error(error.InputError("No cache path provided"))
    ["--cache", cache_path, ..args] | ["-C", cache_path, ..args] ->
      case parsed.cache_path {
        None ->
          do_parse_args(
            args,
            ParsedArgs(..parsed, cache_path: Some(cache_path)),
          )
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
            False -> Ok(ParsedArgs(..parsed, type_flag: True))
          }
        "--value" | "-v" ->
          case parsed.value_flag {
            True -> Error(error.InputError("Flags can only be specified once"))
            False -> Ok(ParsedArgs(..parsed, value_flag: True))
          }
        "--help" | "-h" ->
          case parsed.help_flag {
            True -> Error(error.InputError("Flags can only be specified once"))
            False -> Ok(ParsedArgs(..parsed, help_flag: True))
          }
        "--version" ->
          case parsed.version_flag {
            True -> Error(error.InputError("Flags can only be specified once"))
            False -> Ok(ParsedArgs(..parsed, version_flag: True))
          }
        "--refresh" | "-r" ->
          case parsed.refresh_cache {
            True -> Error(error.InputError("Flags can only be specified once"))
            False -> Ok(ParsedArgs(..parsed, refresh_cache: True))
          }
        "--raw" ->
          case parsed.print_raw {
            True -> Error(error.InputError("Flags can only be specified once"))
            False -> Ok(ParsedArgs(..parsed, print_raw: True))
          }
        _ ->
          case parsed.query {
            Some(_) ->
              Error(error.InputError("Please only specify one name to document"))
            None -> Ok(ParsedArgs(..parsed, query: Some(arg)))
          }
      }
      |> result.try(do_parse_args(args, _))
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
/// The expected input looks like this: [package:]module/name[.item]
/// Parts between brackets can be ommited
///
pub fn parse_query(query: String) -> Result(ParsedQuery, error.Error) {
  use #(package, module_item) <- result.try(case string.split(query, on: ":") {
    [module_item] -> Ok(#(None, module_item))
    ["", _] ->
      Error(error.InputError(
        "No package name found. Try specifying one in your query, for example: `wibble:wobble/mod.item`",
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

  case string.split(module_path, on: "/") {
    ["", ..] ->
      Error(error.InputError(
        "I did not understand what module you are referring to (should respect [package:]main/module.item syntax)",
      ))
    path -> Ok(ParsedQuery(package, path, item))
  }
}
