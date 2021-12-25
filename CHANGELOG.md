## [Unreleased]
## [2.0.1] - 2021-12-26
### Fixed
- write correct arguments

## [2.0.0] - 2021-12-26
### Changed
- refactored codebase to more readable classes
- selenium used only for login and then close => obtain SID (and user with unit)
- login waiting mechanism
### Added
- found way how to change mode & power (tell unit to change)

## [1.4.1] - 2021-12-18
### Changed
- little refactor

## [1.4.0] - 2021-12-12
### Changed
- founded way to get config and data from Atrea server

## [1.3.1] - 2021-12-11
### Changed
- version of selenium

## [1.3.0] - 2021-12-11
### Changed
- store auth tokens outside
- minimize selenium only for login

## [1.2.1] - 2021-10-30
### Changed
- login procedure
- ensure logged user by window.user object

## [1.2.0] - 2021-10-26
### Changed
- use internal unit.php for read values
- reload login automatically if session expire
## [1.1.0] - 2021-10-22
### Added
- to_json

## [1.0.0] - 2021-09-13
- Initial release
