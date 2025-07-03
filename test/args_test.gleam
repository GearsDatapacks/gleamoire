import birdie
import gleam/list
import gleam/option.{None, Some}
import gleamoire/args
import gleamoire/error
import gleamoire/version.{Version}

pub fn args_test() {
  let assert Ok(value) =
    args.parse_args([
      "-t", "lustre.Error", "-C", "~/.cache", "-r", "--raw", "-V", "2.1",
      "--silent",
    ])
  assert value
    == args.Document(
      query: args.ParsedQuery(
        package: None,
        module_path: ["lustre"],
        item: Some("Error"),
      ),
      print_mode: args.Type,
      cache_path: Some("~/.cache"),
      refresh_cache: True,
      print_raw: True,
      package_version: Some(Version(major: 2, minor: 1, patch: 0)),
      silent: True,
    )
}

pub fn help_args_test() {
  let assert Ok(value) = args.parse_args(["--help"])
  assert value == args.Help
}

pub fn version_args_test() {
  let assert Ok(value) = args.parse_args(["--version"])
  assert value == args.PrintVersion
}

pub fn args_tv_error_test() {
  let assert Error(value) = args.parse_args(["gleamoire.main", "-t", "-v"])
  value
  |> error.to_string
  |> birdie.snap("Should report -t and -v error")
}

pub fn args_no_module_error_test() {
  let assert Error(value) = args.parse_args(["--type"])
  value
  |> error.to_string
  |> birdie.snap("Should report no module error")
}

pub fn args_no_cache_path_error_test() {
  let assert Error(value) = args.parse_args(["gleam/int.to_string", "--cache"])
  value
  |> error.to_string
  |> birdie.snap("Should report no cache path error")
}

pub fn args_two_modules_error_test() {
  let assert Error(value) =
    args.parse_args(["gleam/option.to_result", "gleam/result.to_option"])
  value
  |> error.to_string
  |> birdie.snap("Should report error for specifying multiple modules")
}

pub fn args_duplicate_flag_error_test() {
  let assert Error(value) = args.parse_args(["-t", "--type"])
  value
  |> error.to_string
  |> birdie.snap("Should report error for duplicate flags")
}

pub fn args_duplicate_cache_error_test() {
  let assert Error(value) = args.parse_args(["--cache", ".", "-C", ".."])
  value
  |> error.to_string
  |> birdie.snap("Should report error for duplicate cache flags")
}

pub fn parse_query_explicit_package_test() {
  let assert Ok(value) = args.parse_query("wibble:weebble/wobble.bleep")
  assert value
    == args.ParsedQuery(Some("wibble"), ["weebble", "wobble"], Some("bleep"))
}

pub fn parse_query_implicit_package_test() {
  let assert Ok(value) = args.parse_query("wibble/wobble.bleep")
  assert value == args.ParsedQuery(None, ["wibble", "wobble"], Some("bleep"))
}

pub fn parse_query_too_many_packages_test() {
  let assert Error(value) =
    args.parse_query("wibble:wibble:wibble/wobble.bleep")
  value
  |> error.to_string
  |> birdie.snap("Should report too many packages")
}

pub fn parse_query_no_item_test() {
  let assert Ok(value) = args.parse_query("wibble/wobble")
  assert value == args.ParsedQuery(None, ["wibble", "wobble"], None)
}

pub fn parse_query_no_module_item_test() {
  let assert Error(value) = args.parse_query("wibble:")
  value
  |> error.to_string
  |> birdie.snap("Should report wrong query empty module")
}

pub fn parse_query_no_package_test() {
  let assert Error(value) = args.parse_query(":module/main.item")
  value
  |> error.to_string
  |> birdie.snap("Should report wrong query empty package")
}

pub fn parse_query_too_many_items_test() {
  let assert Error(value) = args.parse_query("wibble.wooble.whoopsi")
  value
  |> error.to_string
  |> birdie.snap("Should report too many items")
}

pub fn parse_query_empty_item_test() {
  let assert Error(value) = args.parse_query("wibble.")
  value
  |> error.to_string
  |> birdie.snap("Should report empty item")
}

pub fn parse_full_version_test() {
  let assert Ok(value) = version.parse("0.4.1")
  assert value == Version(0, 4, 1)
}

pub fn parse_version_without_patch_test() {
  let assert Ok(value) = version.parse("3.2")
  assert value == Version(3, 2, 0)
}

pub fn parse_version_only_major_test() {
  let assert Ok(value) = version.parse("1")
  assert value == Version(1, 0, 0)
}

pub fn parse_version_too_many_components_test() {
  let assert Error(value) = version.parse("1.3.5.2")
  assert value == error.InputError("Invalid version number")
}

pub fn parse_version_non_number_test() {
  let assert Error(value) = version.parse("3.2.five")
  assert value == error.InputError("Invalid version number")
}

pub fn version_max_test() {
  let v1 = Version(2, 1, 0)
  let v2 = Version(2, 0, 3)

  assert version.max(v1, v2) == v1
}

pub fn version_max_of_test() {
  let assert Ok(value) =
    ["0.2.4", "2.3", "5.8.1", "3.4.2"]
    |> list.filter_map(version.parse)
    |> version.max_of
  assert value == Version(5, 8, 1)
}

pub fn version_max_of_one_test() {
  let version = Version(0, 1, 1)
  let assert Ok(value) = version.max_of([version])
  assert value == version
}

pub fn version_max_of_none_test() {
  let assert Error(_) = version.max_of([])
}
