import argv
import gleam/io
import gleam/result
import gleam/string
import gleamoire/args.{ParsedQuery, parse_args}
import gleamoire/docs.{get_docs, package_interface}
import gleamoire/error
import gleamoire/markdown

const gleamoire_version = "2.0.0"

/// Entrypoint to gleamoire
///
pub fn main() {
  let result = argv.load().arguments |> parse_args |> result.try(gleamoire)

  case result {
    Ok(docs) -> docs |> string.trim_end |> io.println
    Error(error) -> error |> error.to_string |> io.println_error
  }
}

/// Transforms command line arguments into appropriate output
///
fn gleamoire(args: args.Args) -> Result(String, error.Error) {
  case args {
    args.Help -> Ok(args.help_text)
    args.PrintVersion -> Ok("Gleamoire v" <> gleamoire_version)
    args.Document(
      query:,
      print_mode:,
      cache_path:,
      print_raw:,
      refresh_cache:,
      package_version:,
      silent:,
    ) -> {
      use interface <- result.try(package_interface(
        query,
        cache_path,
        package_version,
        refresh_cache,
        silent,
      ))
      let ParsedQuery(_, module_path, item) = query
      use docs <- result.map(get_docs(interface, module_path, item, print_mode))
      case print_raw {
        True -> docs
        False -> docs |> markdown.render
      }
    }
  }
}
