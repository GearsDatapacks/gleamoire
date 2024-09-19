import birdie
import gleam/list
import gleam/option.{None, Some}
import gleamoire/args
import gleamoire/error
import gleamoire/version.{Version}
import gleeunit/should

pub fn args_test() {
  args.parse_args([
    "-t", "lustre.Error", "-C", "~/.cache", "-r", "--raw", "-V", "2.1",
  ])
  |> should.be_ok
  |> should.equal(args.Document(
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
  ))
}

pub fn help_args_test() {
  args.parse_args(["--help"])
  |> should.be_ok
  |> should.equal(args.Help)
}

pub fn version_args_test() {
  args.parse_args(["--version"])
  |> should.be_ok
  |> should.equal(args.PrintVersion)
}

pub fn args_tv_error_test() {
  args.parse_args(["gleamoire.main", "-t", "-v"])
  |> should.be_error
  |> error.to_string
  |> birdie.snap("Should report -t and -v error")
}

pub fn args_no_module_error_test() {
  args.parse_args(["--type"])
  |> should.be_error
  |> error.to_string
  |> birdie.snap("Should report no module error")
}

pub fn args_no_cache_path_error_test() {
  args.parse_args(["gleam/int.to_string", "--cache"])
  |> should.be_error
  |> error.to_string
  |> birdie.snap("Should report no cache path error")
}

pub fn args_two_modules_error_test() {
  args.parse_args(["gleam/option.to_result", "gleam/result.to_option"])
  |> should.be_error
  |> error.to_string
  |> birdie.snap("Should report error for specifying multiple modules")
}

pub fn args_duplicate_flag_error_test() {
  args.parse_args(["-t", "--type"])
  |> should.be_error
  |> error.to_string
  |> birdie.snap("Should report error for duplicate flags")
}

pub fn args_duplicate_cache_error_test() {
  args.parse_args(["--cache", ".", "-C", ".."])
  |> should.be_error
  |> error.to_string
  |> birdie.snap("Should report error for duplicate cache flags")
}

pub fn parse_query_explicit_package_test() {
  args.parse_query("wibble:weebble/wobble.bleep")
  |> should.be_ok
  |> should.equal(args.ParsedQuery(
    Some("wibble"),
    ["weebble", "wobble"],
    Some("bleep"),
  ))
}

pub fn parse_query_implicit_package_test() {
  args.parse_query("wibble/wobble.bleep")
  |> should.be_ok
  |> should.equal(args.ParsedQuery(None, ["wibble", "wobble"], Some("bleep")))
}

pub fn parse_query_too_many_packages_test() {
  args.parse_query("wibble:wibble:wibble/wobble.bleep")
  |> should.be_error
  |> error.to_string
  |> birdie.snap("Should report too many packages")
}

pub fn parse_query_no_item_test() {
  args.parse_query("wibble/wobble")
  |> should.be_ok
  |> should.equal(args.ParsedQuery(None, ["wibble", "wobble"], None))
}

pub fn parse_query_no_module_item_test() {
  args.parse_query("wibble:")
  |> should.be_error
  |> error.to_string
  |> birdie.snap("Should report wrong query empty module")
}

pub fn parse_query_no_package_test() {
  args.parse_query(":module/main.item")
  |> should.be_error
  |> error.to_string
  |> birdie.snap("Should report wrong query empty package")
}

pub fn parse_query_too_many_items_test() {
  args.parse_query("wibble.wooble.whoopsi")
  |> should.be_error
  |> error.to_string
  |> birdie.snap("Should report too many items")
}

pub fn parse_query_empty_item_test() {
  args.parse_query("wibble.")
  |> should.be_error
  |> error.to_string
  |> birdie.snap("Should report empty item")
}

pub fn parse_full_version_test() {
  version.parse("0.4.1")
  |> should.be_ok
  |> should.equal(Version(0, 4, 1))
}

pub fn parse_version_without_patch_test() {
  version.parse("3.2")
  |> should.be_ok
  |> should.equal(Version(3, 2, 0))
}

pub fn parse_version_only_major_test() {
  version.parse("1")
  |> should.be_ok
  |> should.equal(Version(1, 0, 0))
}

pub fn parse_version_too_many_components_test() {
  version.parse("1.3.5.2")
  |> should.be_error
  |> should.equal(error.InputError("Invalid version number"))
}

pub fn parse_version_non_number_test() {
  version.parse("3.2.five")
  |> should.be_error
  |> should.equal(error.InputError("Invalid version number"))
}

pub fn version_max_test() {
  let v1 = Version(2, 1, 0)
  let v2 = Version(2, 0, 3)

  version.max(v1, v2)
  |> should.equal(v1)
}

pub fn version_max_of_test() {
  ["0.2.4", "2.3", "5.8.1", "3.4.2"]
  |> list.filter_map(version.parse)
  |> version.max_of
  |> should.be_ok
  |> should.equal(Version(5, 8, 1))
}

pub fn version_max_of_one_test() {
  let version = Version(0, 1, 1)
  version.max_of([version])
  |> should.be_ok
  |> should.equal(version)
}

pub fn version_max_of_none_test() {
  version.max_of([]) |> should.be_error
}
