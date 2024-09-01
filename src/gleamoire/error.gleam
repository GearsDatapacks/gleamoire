/// Possible errors in geamoire
///
pub type Error {
  /// Something went wrong with user input
  InputError(String)
  /// Error regarding package interface
  InterfaceError(String)
  /// Something went wrong with IO
  FileError(String)
  /// Something went wrong when building local docs
  BuildError(String)
  /// No idea what went wrong, but something did definitely go wrong
  UnexpectedError(String)
}

/// Convert an Error in order to display
///
pub fn to_string(error: Error) -> String {
  case error {
    InputError(message) -> "InputError: " <> message
    InterfaceError(message) -> "InterfaceError: " <> message
    FileError(message) -> "FileError: " <> message
    BuildError(message) -> "BuildError: " <> message
    UnexpectedError(message) -> "Unexpected error: " <> message
  }
}
