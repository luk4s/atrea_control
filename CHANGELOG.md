## [Unreleased]
## [3.1.0] - 2025-11-14
### Changed
- upgrade dependencies
- replace RestClient by Faraday

## [3.0.1] - 2025-03-17
### Security
- upgrade gems
### Change
- update rubocop (plugins)

## [3.0.0] - 2025-01-25
### Removed
- selenium-based login procedure
### Added
- token / phpsessionid-based login in background
- "session" validity check & expiration (exception)
### Changed
- ruby version 3.3+
- 
## [2.2.0] - 2024-10-20
### Added
- timestamp from atrea server
### Changed
- upgrade dependencies
- upgrade ruby version

## [2.2.0] - 2023-10-09
### Changed
- update dependencies

## [2.1.3] - 2023-02-04
### Fixed
- preheating is always boolean, so no need !! => which coused reverse right now...

## [2.1.2] - 2023-02-03
### Fixed
- selenium-webdriver deprecations
- some code-style/rubocop offenses
## [2.1.1] - 2022-08-21
### Fixed
- override "schedule program" by "temporary"
### Changed
- dependencies update

## [2.1.0] - 2022-02-28
### Added
- preheating  is ON ?
- heat temperature
- current input temperature
### Removed
- debug

## [2.0.2] - 2022-01-20
### Added
- debug unit values
- try token-based login (without success)

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
