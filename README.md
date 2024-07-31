# Gleamoire

Gleamoire is a tool for documenting Gleam modules in the command line, inspired by `pydoc`.

## Usage
Run `gleamoire --help` to see a full usage guide.

### Viewing documentation
To use Gleamoire to view documentation for a module, function or type, simply run:
```sh
gleamoire <module path>
```

For example:
```sh
gleamoire gleam/io.println
```
Would document the `println` function of the `gleam/io` package.

Sometimes there are a type and value with the same name, for example:
```gleam
// mod.gleam
pub type Thing {
  Thing
  OtherThing
}
```
Here, `mod.Thing` can refer to the type `Thing`, or the value `Thing`.

To fix this ambiguity, use the `-v` flag to print the value, or the `-t` flag for the type:
```sh
gleamoire mod.Thing -v # Documents the `Thing` value
gleamoire mod.Thing -t # Documents the `Thing` type
```
