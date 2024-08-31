import birdie
import gleam/dict
import gleam/option.{None, Some}
import gleam/package_interface as pi
import gleam/string
import gleamoire
import gleamoire/args
import gleamoire/error
import gleamoire/render
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

fn empty_module() {
  pi.Module(
    documentation: [],
    type_aliases: dict.new(),
    types: dict.new(),
    constants: dict.new(),
    functions: dict.new(),
  )
}

fn empty_package() {
  pi.Package(
    name: "pack",
    version: "1.0.0",
    gleam_version_constraint: None,
    modules: dict.new(),
  )
}

fn gleam_type(name: String) -> pi.Type {
  pi.Named(name:, package: "gleam", module: "gleam", parameters: [])
}

const implementations = pi.Implementations(True, False, False)

pub fn module_documentation_test() {
  render.document_module(
    "mod",
    pi.Module(
      ..empty_module(),
      documentation: [
        "# The mod module", "## This is a subheading", "This module does things",
      ],
    ),
    empty_package(),
  )
  |> birdie.snap("Should print module documentation")
}

pub fn module_items_test() {
  render.document_module(
    "mod2",
    pi.Module(
      documentation: [
        "# The other module, mod2", "## Another subheading",
        "This module does other things",
      ],
      type_aliases: [
        #(
          "MyAlias",
          pi.TypeAlias(
            documentation: None,
            deprecation: None,
            parameters: 1,
            alias: pi.Variable(1),
          ),
        ),
      ]
        |> dict.from_list(),
      types: [
        #(
          "MyType",
          pi.TypeDefinition(
            documentation: None,
            deprecation: None,
            parameters: 0,
            constructors: [
              pi.TypeConstructor(
                documentation: None,
                name: "MyConstructor",
                parameters: [],
              ),
            ],
          ),
        ),
      ]
        |> dict.from_list(),
      constants: [
        #(
          "my_constant",
          pi.Constant(
            documentation: None,
            deprecation: None,
            implementations:,
            type_: gleam_type("Int"),
          ),
        ),
      ]
        |> dict.from_list(),
      functions: [
        #(
          "my_function",
          pi.Function(
            documentation: None,
            deprecation: None,
            implementations:,
            parameters: [],
            return: gleam_type("Nil"),
          ),
        ),
      ]
        |> dict.from_list(),
    ),
    empty_package(),
  )
  |> birdie.snap("Should print module items")
}

pub fn module_submodule_test() {
  render.document_module(
    "mod",
    pi.Module(
      ..empty_module(),
      documentation: [
        "# The mod module", "## This is a subheading", "This module does things",
      ],
    ),
    pi.Package(
      ..empty_package(),
      modules: [
          #("mod/sub", empty_module()),
          #("mod/sub2", empty_module()),
          #("mod/sub/other", empty_module()),
        ]
        |> dict.from_list,
    ),
  )
  |> birdie.snap("Should print submodules of a module")
}

pub fn constant_item_test() {
  render.document_item(
    "constant",
    "module",
    pi.Module(
      ..empty_module(),
      constants: [
          #(
            "constant",
            pi.Constant(
              documentation: Some("This holds a constant value"),
              deprecation: None,
              implementations:,
              type_: pi.Named(
                name: "Option",
                package: "gleam_stdlib",
                module: "gleam/option",
                parameters: [gleam_type("Int")],
              ),
            ),
          ),
        ]
        |> dict.from_list,
    ),
    empty_package(),
    args.Unspecified,
  )
  |> should.be_ok
  |> birdie.snap("Should print module constant")
}

pub fn function_item_test() {
  render.document_item(
    "func",
    "module",
    pi.Module(
      ..empty_module(),
      functions: [
          #(
            "func",
            pi.Function(
              documentation: Some("Does stuff"),
              deprecation: None,
              implementations:,
              parameters: [
                pi.Parameter(label: None, type_: gleam_type("Int")),
                pi.Parameter(label: Some("float"), type_: gleam_type("Float")),
              ],
              return: gleam_type("Bool"),
            ),
          ),
        ]
        |> dict.from_list,
    ),
    empty_package(),
    args.Unspecified,
  )
  |> should.be_ok
  |> birdie.snap("Should print module function")
}

pub fn deprecated_item_test() {
  render.document_item(
    "constant",
    "module",
    pi.Module(
      ..empty_module(),
      constants: [
          #(
            "constant",
            pi.Constant(
              documentation: Some("This holds a constant value"),
              deprecation: Some(pi.Deprecation(
                "You don't need a constant for Nil, silly",
              )),
              implementations:,
              type_: gleam_type("Nil"),
            ),
          ),
        ]
        |> dict.from_list,
    ),
    empty_package(),
    args.Unspecified,
  )
  |> should.be_ok
  |> birdie.snap("Should print deprecated module constant")
}

pub fn type_alias_test() {
  render.document_item(
    "Alias",
    "module",
    pi.Module(
      ..empty_module(),
      type_aliases: [
          #(
            "Alias",
            pi.TypeAlias(
              documentation: Some("This is an alias for Result(a, Nil)"),
              deprecation: None,
              parameters: 1,
              alias: pi.Named("Result", "gleam", "gleam", [
                pi.Variable(0),
                gleam_type("Nil"),
              ]),
            ),
          ),
        ]
        |> dict.from_list,
    ),
    empty_package(),
    args.Unspecified,
  )
  |> should.be_ok
  |> birdie.snap("Should print type alias")
}

pub fn type_no_constructor_test() {
  render.document_item(
    "Type",
    "module",
    pi.Module(
      ..empty_module(),
      types: [
          #(
            "Type",
            pi.TypeDefinition(
              documentation: Some("This is a type with no constructors"),
              deprecation: None,
              parameters: 1,
              constructors: [],
            ),
          ),
        ]
        |> dict.from_list,
    ),
    empty_package(),
    args.Unspecified,
  )
  |> should.be_ok
  |> birdie.snap("Should print type without constructors")
}

pub fn custom_type_test() {
  render.document_item(
    "MyResult",
    "module",
    pi.Module(
      ..empty_module(),
      types: [
          #(
            "MyResult",
            pi.TypeDefinition(
              documentation: Some("Custom implementation of Result type"),
              deprecation: Some(pi.Deprecation("Just use Result")),
              parameters: 2,
              constructors: [
                pi.TypeConstructor(
                  documentation: Some("The Ok value"),
                  name: "Ok",
                  parameters: [
                    pi.Parameter(Some("value"), pi.Variable(0)),
                    pi.Parameter(Some("extra_info"), pi.Variable(1)),
                  ],
                ),
                pi.TypeConstructor(
                  documentation: Some("The Error value"),
                  name: "Error",
                  parameters: [
                    pi.Parameter(Some("message"), gleam_type("String")),
                  ],
                ),
              ],
            ),
          ),
        ]
        |> dict.from_list,
    ),
    empty_package(),
    args.Unspecified,
  )
  |> should.be_ok
  |> birdie.snap("Should print custom type")
}

pub fn unknown_item_error_test() {
  render.document_item(
    "NonExistent",
    "module",
    empty_module(),
    empty_package(),
    args.Unspecified,
  )
  |> should.be_error
  |> error.to_string
  |> birdie.snap("Should error because value doesn't exist")
}

pub fn item_conflict_error_test() {
  render.document_item(
    "Wibble",
    "module",
    pi.Module(
      ..empty_module(),
      types: [
          #(
            "Wibble",
            pi.TypeDefinition(
              documentation: None,
              deprecation: None,
              parameters: 0,
              constructors: [
                pi.TypeConstructor(
                  documentation: None,
                  name: "Wibble",
                  parameters: [],
                ),
              ],
            ),
          ),
        ]
        |> dict.from_list,
    ),
    empty_package(),
    args.Unspecified,
  )
  |> should.be_error
  |> error.to_string
  |> birdie.snap("Should error because of name conflict")
}

pub fn item_conflict_resolution_test() {
  render.document_item(
    "Wibble",
    "module",
    pi.Module(
      ..empty_module(),
      types: [
          #(
            "Wibble",
            pi.TypeDefinition(
              documentation: None,
              deprecation: None,
              parameters: 0,
              constructors: [
                pi.TypeConstructor(
                  documentation: None,
                  name: "Wibble",
                  parameters: [],
                ),
              ],
            ),
          ),
        ]
        |> dict.from_list,
    ),
    empty_package(),
    args.Type,
  )
  |> should.be_ok
  |> birdie.snap("Should print type with name")
}

pub fn args_test() {
  args.parse(["-t", "lustre.Error", "-C", "~/.cache", "-r"])
  |> should.be_ok
  |> string.inspect
  |> birdie.snap("Should parse all arguments")
}

pub fn help_args_test() {
  args.parse(["--help"])
  |> should.be_ok
  |> should.equal(args.Help)
}

pub fn version_args_test() {
  args.parse(["--version"])
  |> should.be_ok
  |> should.equal(args.Version)
}

pub fn args_tv_error_test() {
  args.parse(["gleamoire.main", "-t", "-v"])
  |> should.be_error
  |> error.to_string
  |> birdie.snap("Should report -t and -v error")
}

pub fn args_no_module_error_test() {
  args.parse(["--type"])
  |> should.be_error
  |> error.to_string
  |> birdie.snap("Should report no module error")
}

pub fn args_no_cache_path_error_test() {
  args.parse(["gleam/int.to_string", "--cache"])
  |> should.be_error
  |> error.to_string
  |> birdie.snap("Should report no cache path error")
}

pub fn args_two_modules_error_test() {
  args.parse(["gleam/option.to_result", "gleam/result.to_option"])
  |> should.be_error
  |> error.to_string
  |> birdie.snap("Should report error for specifying multiple modules")
}

pub fn args_duplicate_flag_error_test() {
  args.parse(["-t", "--type"])
  |> should.be_error
  |> error.to_string
  |> birdie.snap("Should report error for duplicate flags")
}

pub fn args_duplicate_cache_error_test() {
  args.parse(["--cache", ".", "-C", ".."])
  |> should.be_error
  |> error.to_string
  |> birdie.snap("Should report error for duplicate cache flags")
}

pub fn parse_query_explicit_package_test() {
  gleamoire.parse_query("wibble:weebble/wobble.bleep")
  |> should.be_ok
  |> should.equal(gleamoire.ParsedQuery(
    Some("wibble"),
    ["weebble", "wobble"],
    Some("bleep"),
  ))
}

pub fn parse_query_implicit_package_test() {
  gleamoire.parse_query("wibble/wobble.bleep")
  |> should.be_ok
  |> should.equal(gleamoire.ParsedQuery(
    None,
    ["wibble", "wobble"],
    Some("bleep"),
  ))
}

pub fn parse_query_too_many_packages_test() {
  gleamoire.parse_query("wibble:wibble:wibble/wobble.bleep")
  |> should.be_error
  |> error.to_string
  |> birdie.snap("Should report too many packages")
}

pub fn parse_query_no_item_test() {
  gleamoire.parse_query("wibble/wobble")
  |> should.be_ok
  |> should.equal(gleamoire.ParsedQuery(None, ["wibble", "wobble"], None))
}

pub fn parse_query_no_module_item_test() {
  gleamoire.parse_query("wibble:")
  |> should.be_error
  |> error.to_string
  |> birdie.snap("Should report wrong query empty module")
}

pub fn parse_query_no_package_test() {
  gleamoire.parse_query(":module/main.item")
  |> should.be_error
  |> error.to_string
  |> birdie.snap("Should report wrong query empty package")
}

pub fn parse_query_too_many_items_test() {
  gleamoire.parse_query("wibble.wooble.whoopsi")
  |> should.be_error
  |> error.to_string
  |> birdie.snap("Should report too many items")
}

pub fn parse_query_empty_item_test() {
  gleamoire.parse_query("wibble.")
  |> should.be_error
  |> error.to_string
  |> birdie.snap("Should report empty item")
}
