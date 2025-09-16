import birdie
import gleam/dict
import gleam/option.{None, Some}
import gleam/package_interface as pi
import gleamoire/args
import gleamoire/docs
import gleamoire/error
import gleamoire/render

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
    pi.Module(..empty_module(), documentation: [
      "# The mod module", "## This is a subheading", "This module does things",
    ]),
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
    pi.Module(..empty_module(), documentation: [
      "# The mod module", "## This is a subheading", "This module does things",
    ]),
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
  let assert Ok(value) =
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
  birdie.snap(value, "Should print module constant")
}

pub fn function_item_test() {
  let assert Ok(value) =
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
  birdie.snap(value, "Should print module function")
}

pub fn deprecated_item_test() {
  let assert Ok(value) =
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
  birdie.snap(value, "Should print deprecated module constant")
}

pub fn type_alias_test() {
  let assert Ok(value) =
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
  birdie.snap(value, "Should print type alias")
}

pub fn type_no_constructor_test() {
  let assert Ok(value) =
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
  birdie.snap(value, "Should print type without constructors")
}

pub fn custom_type_test() {
  let assert Ok(value) =
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
  birdie.snap(value, "Should print custom type")
}

pub fn unknown_item_error_test() {
  let assert Error(value) =
    render.document_item(
      "NonExistent",
      "module",
      empty_module(),
      empty_package(),
      args.Unspecified,
    )
  value
  |> error.to_string
  |> birdie.snap("Should error because value doesn't exist")
}

pub fn item_conflict_error_test() {
  let assert Error(value) =
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
  value
  |> error.to_string
  |> birdie.snap("Should error because of name conflict")
}

pub fn item_conflict_resolution_test() {
  let assert Ok(value) =
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
  birdie.snap(value, "Should print type with name")
}

pub fn qualify_type_test() {
  let assert Ok(value) =
    render.document_item(
      "Wibble",
      "wibble/wobble",
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
                    parameters: [pi.Parameter(None, gleam_type("Int"))],
                  ),
                  pi.TypeConstructor(
                    documentation: None,
                    name: "Wobble",
                    parameters: [
                      pi.Parameter(
                        None,
                        pi.Named(
                          name: "Dict",
                          package: "gleam_stdlib",
                          module: "gleam/dict",
                          parameters: [gleam_type("String"), gleam_type("Int")],
                        ),
                      ),
                    ],
                  ),
                  pi.TypeConstructor(
                    documentation: None,
                    name: "Wubble",
                    parameters: [
                      pi.Parameter(
                        None,
                        pi.Named(
                          name: "Wibble",
                          package: "package",
                          module: "wibble/wobble",
                          parameters: [],
                        ),
                      ),
                    ],
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
  birdie.snap(value, "Should qualify type outside current module")
}

pub fn pull_known_package_test() {
  let assert Ok(value) = docs.get_remote_interface("argv", None, True)
  birdie.snap(value, "Got argv documentation from Hex")
}

pub fn pull_unknown_package_test() {
  let assert Error(value) =
    docs.get_remote_interface("impossibly_impossible_name_to_guess", None, True)
  value
  |> error.to_string
  |> birdie.snap("Should report unknown package on hex")
}

pub fn document_prelude_test() {
  let query =
    args.ParsedQuery(package: None, module_path: ["gleam"], item: None)
  let assert Ok(interface) =
    docs.package_interface(query, None, None, False, True)
  let args.ParsedQuery(_, module_path, item) = query
  let assert Ok(value) =
    docs.get_docs(interface, module_path, item, args.Unspecified)
  birdie.snap(value, "Should document the gleam prelude module")
}

pub fn document_prelude_item_test() {
  let query =
    args.ParsedQuery(
      package: None,
      module_path: ["gleam"],
      item: Some("Result"),
    )
  let assert Ok(interface) =
    docs.package_interface(query, None, None, False, True)
  let args.ParsedQuery(_, module_path, item) = query
  let assert Ok(value) =
    docs.get_docs(interface, module_path, item, args.Unspecified)
  birdie.snap(value, "Should document a gleam prelude item")
}

pub fn sorted_types_test() {
  let value =
    render.document_module(
      "module",
      pi.Module(
        ..empty_module(),
        types: [
            #(
              "MyType",
              pi.TypeDefinition(
                documentation: None,
                deprecation: None,
                parameters: 0,
                constructors: [],
              ),
            ),
            #(
              "SomethingElse",
              pi.TypeDefinition(
                documentation: None,
                deprecation: None,
                parameters: 0,
                constructors: [],
              ),
            ),
            #(
              "ADifferentType",
              pi.TypeDefinition(
                documentation: None,
                deprecation: None,
                parameters: 0,
                constructors: [],
              ),
            ),
          ]
          |> dict.from_list,
      ),
      empty_package(),
    )
  birdie.snap(value, "Should print types in alphabetical order")
}

pub fn sorted_values_test() {
  let value =
    render.document_module(
      "module",
      pi.Module(
        ..empty_module(),
        functions: [
            #(
              "function",
              pi.Function(
                documentation: None,
                deprecation: None,
                implementations:,
                parameters: [],
                return: gleam_type("Nil"),
              ),
            ),
            #(
              "another_function",
              pi.Function(
                documentation: None,
                deprecation: None,
                implementations:,
                parameters: [],
                return: gleam_type("Nil"),
              ),
            ),
          ]
          |> dict.from_list,
      ),
      empty_package(),
    )
  birdie.snap(value, "Should print values in alphabetical order")
}
