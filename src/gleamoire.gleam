import argv
import gleam/io
import glint

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
    [module, ..] ->
      io.println(
        "Welcome to gleamoire! You decided to document "
        <> module
        <> "\nTODO: Actually document :)",
      )
  }
}

pub fn main() {
  glint.new()
  |> glint.with_name("gleamoire")
  |> glint.pretty_help(glint.default_pretty_help())
  |> glint.add(at: [], do: document())
  |> glint.run(argv.load().arguments)
}
