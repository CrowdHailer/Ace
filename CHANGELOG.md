# Change Log
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/)
and this project adheres to [Semantic Versioning](http://semver.org/).

## [0.5.0](https://github.com/CrowdHailer/Ace/tree/0.4.0) - 2016-10-07

## Added
- How to hande a tcp connection is specified by an application server module.

## [0.4.0](https://github.com/CrowdHailer/Ace/tree/0.4.0) - 2016-10-06

## Added
- System sends welcome message.
- System sends data messages over the socket.

### Changed
- Starting a server no longer blocks until the connection has been closed.

## [0.3.0](https://github.com/CrowdHailer/Ace/tree/0.3.0) - 2016-10-04

## Added
- Dialyzer for static analysis, with updated contributing instructions.

### Changed
- Nothing, only bumped version due to incorrect publishing on hex.

## [0.2.0](https://github.com/CrowdHailer/Ace/tree/0.2.0) - 2016-10-04

## Added
- ExUnit test suit and single test case.
- ExDoc for first hex published version.

### Changed
- Restructured to a mix project. Follow new start up instructions in README.

## [0.1.1](https://github.com/CrowdHailer/Ace/tree/0.1.1) - 2016-10-03

### Fixed

- Handle socket closed by client.

## [0.1.0](https://github.com/CrowdHailer/Ace/tree/0.1.0) - 2016-09-18

### Added

- The simplest TCP echo server.
- All code exists in a single source file `server.ex`.
- Documentation is added to the [source code](https://github.com/CrowdHailer/Ace/blob/master/server.ex).
