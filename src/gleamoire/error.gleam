pub type Error {
  InputError(String)
  InterfaceError(String)
  UnexpectedError(String)
}

pub fn to_string(error: Error) -> String {
  case error {
    InputError(message) -> "InputError: " <> message
    InterfaceError(message) -> "InterfaceError: " <> message
    UnexpectedError(message) -> "Unexpected error: " <> message
  }
}
