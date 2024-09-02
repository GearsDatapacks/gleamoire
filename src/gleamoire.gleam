import argv
import gleam/io
import gleam/result
import gleam/string
import gleamoire/args.{type ParsedQuery, ParsedQuery, parse_args}
import gleamoire/docs.{get_docs, package_interface}
import gleamoire/error

const gleamoire_version = "1.0.0"

/// Entrypoint to gleamoire
///
pub fn main() {
  let result = argv.load().arguments |> parse_args |> result.try(gleamoire)

  case result {
    Ok(docs) -> docs |> string.trim_right |> io.println
    Error(error) -> io.println(error.to_string(error))
  }
}

/// Transforms command line arguments into appropriate output
///
fn gleamoire(args: args.Args) -> Result(String, error.Error) {
  case args {
    args.Help -> Ok(args.help_text)
    args.Version -> Ok("Gleamoire v" <> gleamoire_version)
    args.Document(query:, print_mode:, cache_path:, refresh_cache:) -> {
      use interface <- result.try(package_interface(
        query,
        cache_path,
        refresh_cache,
      ))
      let assert ParsedQuery(_, [main_module, ..sub], item) = query
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
