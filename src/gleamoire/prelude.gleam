//// Special handling of the Gleam prelude

import gleam/dict
import gleam/option.{None, Some}
import gleam/package_interface as pi
import gleam/string

// This can't be a constant because we need to use dict.from_list
pub fn prelude_interface() {
  pi.Package(
    name: "gleam",
    version: "1.0.0",
    gleam_version_constraint: None,
    modules: [
      #(
        "gleam",
        pi.Module(
          documentation: [
            "The gleam prelude. Types and values built into the compiler, representing",
            "features which interact directly with the language, and therefore cannot",
            "be defined in Gleam itself.",
            note,
          ],
          type_aliases: dict.new(),
          types: [
            #(
              "BitArray",
              pi.TypeDefinition(
                documentation: Some(
                  [
                    "Bit arrays represent a sequence of 1s and 0s, and are a convenient syntax for constructing and manipulating binary data.",
                    "",
                    "Each segment of a bit array can be given options to specify the representation used for that segment.",
                    "",
                    "`size`: the size of the segment in bits.",
                    "`unit`: the number of bits that the size value is a multiple of.",
                    "`bits`: a nested bit array of any size.",
                    "`bytes`: a nested byte-aligned bit array.",
                    "`float`: a 64 bits floating point number.",
                    "`int`: an int with a default size of 8 bits.",
                    "`big`: big endian.",
                    "`little`: little endian.",
                    "`native`: the endianness of the processor.",
                    "`utf8`: utf8 encoded text.",
                    "`utf16`: utf16 encoded text.",
                    "`utf32`: utf32 encoded text.",
                    "`utf8_codepoint`: a utf8 codepoint.",
                    "`utf16_codepoint`: a utf16 codepoint.",
                    "`utf32_codepoint`: a utf32 codepoint.",
                    "`signed`: a signed number.",
                    "`unsigned`: an unsigned number.",
                    "",
                    " Bit arrays have limited support when compiling to JavaScript, not all options can be used. Full bit array support will be implemented in the future. ",
                    note,
                  ]
                  |> string.join("\n"),
                ),
                deprecation: None,
                parameters: 0,
                constructors: [],
              ),
            ),
            #(
              "Bool",
              pi.TypeDefinition(
                documentation: Some(
                  ["A boolean value, either `True` or `False`.", note]
                  |> string.join("\n"),
                ),
                deprecation: None,
                parameters: 0,
                constructors: [
                  pi.TypeConstructor(
                    documentation: Some(
                      ["The truthy boolean value.", note] |> string.join("\n"),
                    ),
                    name: "True",
                    parameters: [],
                  ),
                  pi.TypeConstructor(
                    documentation: Some(
                      ["The falsey boolean value.", note] |> string.join("\n"),
                    ),
                    name: "False",
                    parameters: [],
                  ),
                ],
              ),
            ),
            #(
              "Float",
              pi.TypeDefinition(
                documentation: Some(
                  [
                    "The floating point, represention numbers which are not integers.",
                    "",
                    "Floats have dedicated mathematical operators, distinct from integer operators.",
                    "Floating point operators are the same as integer operators, but suffixed with `.`. For example, `+.`",
                    "",
                    "Floating point operations have different behaviour on different targets.",
                    "On both targets, division by zero is defined to be zero.",
                    note,
                  ]
                  |> string.join("\n"),
                ),
                deprecation: None,
                parameters: 0,
                constructors: [],
              ),
            ),
            #(
              "Int",
              pi.TypeDefinition(
                documentation: Some(
                  [
                    "The integer type, for representing whole numbers.",
                    "",
                    "Integers have no maximum or minimum value on Erlang target.",
                    "On javascript, integers are represented as 64-bit floating point numbers.",
                    note,
                  ]
                  |> string.join("\n"),
                ),
                deprecation: None,
                parameters: 0,
                constructors: [],
              ),
            ),
            #(
              "List",
              pi.TypeDefinition(
                documentation: Some(
                  [
                    "An ordered collection of values.",
                    "",
                    "Lists have one generic parameter: The type of the list's elements.",
                    "A list can only contain elements of one type.",
                    "",
                    "Lists are immutable single-linked lists, meaning they are very efficient to add and remove elements from the front of the list.",
                    "Counting the length of a list or getting elements from other positions in the list is expensive and rarely done.",
                    note,
                  ]
                  |> string.join("\n"),
                ),
                deprecation: None,
                parameters: 1,
                constructors: [],
              ),
            ),
            #(
              "Nil",
              pi.TypeDefinition(
                documentation: Some([note] |> string.join("\n")),
                deprecation: None,
                parameters: 0,
                constructors: [
                  pi.TypeConstructor(
                    documentation: Some(
                      [
                        "Nil is Gleam's unit type. It is a value that is returned by functions that have",
                        "nothing else to return, as all functions must return something.",
                        "",
                        "Nil is not a valid value of any other types. Therefore, values in Gleam are not nullable.",
                        "If the type of a value is Nil then it is the value Nil.",
                        "If it is some other type then the value is not Nil.",
                        note,
                      ]
                      |> string.join("\n"),
                    ),
                    name: "Nil",
                    parameters: [],
                  ),
                ],
              ),
            ),
            #(
              "Result",
              pi.TypeDefinition(
                documentation: Some(
                  [
                    "The result of a fallible operation. A generic type, with two parameters:",
                    "The value in case of a success, and the value representing any error encountered.",
                    "",
                    "Commonly a Gleam program or library will define a custom type with a variant for each",
                    "possible problem that can arise, along with any error information that would be useful to the programmer.",
                    note,
                  ]
                  |> string.join("\n"),
                ),
                deprecation: None,
                parameters: 2,
                constructors: [
                  pi.TypeConstructor(
                    documentation: Some(
                      [
                        "The successful return value of a fallible operation.",
                        note,
                      ]
                      |> string.join("\n"),
                    ),
                    name: "Ok",
                    parameters: [
                      pi.Parameter(label: None, type_: pi.Variable(0)),
                    ],
                  ),
                  pi.TypeConstructor(
                    documentation: Some(
                      ["The error encountered when an operation failed.", note]
                      |> string.join("\n"),
                    ),
                    name: "Error",
                    parameters: [
                      pi.Parameter(label: None, type_: pi.Variable(1)),
                    ],
                  ),
                ],
              ),
            ),
            #(
              "String",
              pi.TypeDefinition(
                documentation: Some(
                  [
                    "A string of text. Strings in Gleam must be valid UTF-8.",
                    note,
                  ]
                  |> string.join("\n"),
                ),
                deprecation: None,
                parameters: 0,
                constructors: [],
              ),
            ),
            #(
              "UtfCodepoint",
              pi.TypeDefinition(
                documentation: Some(
                  ["A single UTF-8 codepoint.", note] |> string.join("\n"),
                ),
                deprecation: None,
                parameters: 0,
                constructors: [],
              ),
            ),
          ]
            |> dict.from_list,
          constants: dict.new(),
          functions: dict.new(),
        ),
      ),
    ]
      |> dict.from_list,
  )
}

const note = "\nNote: The prelude has no official documentation, so all prelude documentation\n"
  <> "is written by the creators of Gleamoire, or taken from the Gleam Language Tour."
