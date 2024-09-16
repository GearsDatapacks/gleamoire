import gleam/int
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import gleamoire/error

pub type Version {
  Version(major: Int, minor: Int, patch: Int)
}

const invalid_version = error.InputError("Invalid version number")

pub fn parse(str: String) -> Result(Version, error.Error) {
  let parts = str |> string.split(".")
  case parts {
    [major, minor, patch] -> {
      use major <- result.try(
        int.parse(major) |> result.replace_error(invalid_version),
      )
      use minor <- result.try(
        int.parse(minor) |> result.replace_error(invalid_version),
      )
      use patch <- result.map(
        int.parse(patch) |> result.replace_error(invalid_version),
      )
      Version(major:, minor:, patch:)
    }
    [major, minor] -> {
      use major <- result.try(
        int.parse(major) |> result.replace_error(invalid_version),
      )
      use minor <- result.map(
        int.parse(minor) |> result.replace_error(invalid_version),
      )
      Version(major:, minor:, patch: 0)
    }
    [major] -> {
      use major <- result.map(
        int.parse(major) |> result.replace_error(invalid_version),
      )
      Version(major:, minor: 0, patch: 0)
    }
    _ -> Error(invalid_version)
  }
}

pub fn to_string(version: Version) -> String {
  int.to_string(version.major)
  <> "."
  <> int.to_string(version.minor)
  <> "."
  <> int.to_string(version.patch)
}

/// Returns the highest version out of a list of version numbers. Returns Error
/// if passed an empty list
pub fn max_of(versions: List(Version)) -> Result(Version, Nil) {
  case versions {
    [] -> Error(Nil)
    [first] -> Ok(first)
    [first, ..rest] -> Ok(list.fold(rest, first, max))
  }
}

fn max(v1: Version, v2: Version) -> Version {
  let v1_greater =
    v1.major > v2.major || v1.minor > v2.minor || v1.patch > v2.patch
  case v1_greater {
    True -> v1
    False -> v2
  }
}

/// The result of version resolution
pub type ResolvedVersion {
  /// The version could not be resolved, so default to the latest
  Unresolved
  /// The version was specified explicitly by the user, so no resolution was required
  Specified(Version)
  /// The version could be determined using version resolution
  Resolved(Version)
}

pub fn to_option(v: ResolvedVersion) -> option.Option(Version) {
  case v {
    Resolved(v) | Specified(v) -> option.Some(v)
    Unresolved -> option.None
  }
}
