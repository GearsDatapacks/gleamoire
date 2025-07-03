# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 2.0.0 - 2025-07-03

- Added the `--silent` flag, which removes the printing of progress when fetching
  or building documentation.
- Modules other than the main `gleamoire` module have been made internal.

## 1.1.0 - 2025-03-09

- The list of stdlib modules has been updated to include newly added modules
  and deprecated/removed modules.
- Gleamoire no longer runs `gleam clean` when building documentation, as the bug
  in the compiler requiring that has now been fixed.

## 1.0.0 - 2024-09-28
Initial Release

### Added
- The ability to document modules, types and values
- Markdown rendering
- Specifying specific package versions
- Versioned documentation cache
- Documentation for the Gleam Prelude
