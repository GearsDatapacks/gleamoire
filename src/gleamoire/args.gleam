import gleam/option.{type Option, None, Some}
import gleam/result
import gleamoire/error

pub type Args {
  Help
  Document(module: String, print_mode: PrintMode, cache_path: Option(String))
}

pub type PrintMode {
  Unspecified
  Type
  Value
}

pub const help_text = "Documents a gleam module, type or value, in the command line!

Usage:
gleamoire <module> [flags]

Flags:
--help, -h   Print this help text
--type, -t   Print the type associated with the given name
--value, -v  Print the value associated with the given name
--cache, -C  Use a different cache location for package-interface.json"

pub fn parse(args: List(String)) -> Result(Args, error.Error) {
  use parsed <- result.try(do_parse_args(
    args,
    Parsed(
      value_flag: False,
      type_flag: False,
      help_flag: False,
      module: None,
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
    Parsed(module: Some(module), cache_path:, ..) ->
      Ok(Document(module, print_mode, cache_path))
    Parsed(module: None, help_flag: False, ..) ->
      Error(error.InputError(
        "Please specify a module to document. See gleamoire --help for more information",
      ))
  }
}

type Parsed {
  Parsed(
    value_flag: Bool,
    type_flag: Bool,
    help_flag: Bool,
    cache_path: Option(String),
    module: Option(String),
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
      use parsed <- result.try(case arg {
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
        _ ->
          case parsed.module {
            Some(_) ->
              Error(error.InputError(
                "Please only specify one module to document",
              ))
            None -> Ok(Parsed(..parsed, module: Some(arg)))
          }
      })
      do_parse_args(args, parsed)
    }
  }
}
