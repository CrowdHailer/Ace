# Change Log
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/)
and this project adheres to [Semantic Versioning](http://semver.org/).

## [0.11.1](https://github.com/CrowdHailer/Ace/tree/0.11.1) - 2017-08-03

## Added
- Client for HTTP/2.0.

## [0.11.0](https://github.com/CrowdHailer/Ace/tree/0.11.0) - 2017-08-01

## Added
- Casting for accepted values for each known setting.
- Flow control for outbound data.

## Changed
- Creating priority frame requires exclusive value.

## Fixed
- Graceful handling of closed connections.
- Correctly keep state for multiple connection frames.
- Discard trailers sent to Raxx handler.
- Frames of unknown type are discarded.
- Ignores unknown flags for each frame type.
- Ignores value of reserved bit in frame head.
- Ensure only continuation frames can be sent after end_headers is false.
- Return protocol error for invalid priority frame.
- Return protocol error for invalid rst_stream frame.
- Recognise reseting idle stream as a protocol error.
- Decoding of acked ping frame.
- Correct error codes for invalid window updates.
- Handle unknown error code from client.
- Limit pseudo-headers to those defined in RFC7540.
- All pseudo-headers must be sent before other headers.
- Header keys must be lowercase.
- Pseudo header values cannot be empty.
- Fix off by one error for maximum size of frames.
- Return protocol error for header or data sent after a stream reset.
- Forbid unknown frames to be present in a continuation stream.
- Treat incorrect content length as protocol error.
- Trailing header block must end the stream.
- Protocol error if starting new stream with lower stream_id.
- Disallow flow control windows from exceeding maximum value.

## [0.10.0](https://github.com/CrowdHailer/Ace/tree/0.10.0) - 2017-07-21

## Added
- HTTP/2.0 support via `Ace.HTTP2`

## [0.9.1](https://github.com/CrowdHailer/Ace/tree/0.9.1) - 2017-06-14

## Changed
- Reduced noise from errors of prematurely closed connections

## [0.9.0](https://github.com/CrowdHailer/Ace/tree/0.9.0) - 2017-04-16

## Changed
- Requires Elixir 1.4 and above,
  required applications are now listed as `extra_applications`.

## [0.8.1](https://github.com/CrowdHailer/Ace/tree/0.8.1) - 2017-04-02

## Added
- Warning logged when application module is not using the `Ace.Application` behaviour.

## [0.8.0](https://github.com/CrowdHailer/Ace/tree/0.8.0) - 2017-03-26

## Added
- `Ace.TLS` for tcp/ssl endpoints, matching `Ace.TCP` function profiles.
- `Ace.Connection` to normalise `:gen_tcp`/`:ssl` interfaces.
- Governors can be throttled to zero to drain connections,
  see `Ace.Governor.Supervisor.drain/1`

## Changed
- New connection calls `handle_connect/2` not `init/2`
- Connection lost calls `handle_disconnect/2` not `terminate/2`
- `Ace.TCP` is now the callback module when starting and endpoint,
  there is no `Ace.TCP.Endpoint` module anymore.
- `Ace.Governor` now a `GenServer` to handle OTP sys calls

## Removed
- `Ace.TCP.Server`, now `Ace.Server`.
- `Ace.TCP.Server.Supervisor`, now `Ace.Server.Supervisor`.
- `Ace.TCP.Governor`, now `Ace.Governor`.
- `Ace.TCP.Governor.Supervisor`, now `Ace.Governor.Supervisor`.

## [0.7.1](https://github.com/CrowdHailer/Ace/tree/0.7.1) - 2017-02-13

## Changed
- Startup information is printed using `Logger` and not directly `IO`.

## Fixed
- Remove warnings about bracket use from Elixir 1.4.

## [0.7.0](https://github.com/CrowdHailer/Ace/tree/0.7.0) - 2016-10-26

## Added
- Support a response with a timeout from server modules.
  Passed directly to GenServer so integer and `:hibernate` responses are supported.
- Support closing the connection from the server side.
  It is best to reserver server side closing for misbehaving connections.
- Added callbacks to `Ace.TCP.Server` so that is can be included as a behaviour.

## [0.6.3](https://github.com/CrowdHailer/Ace/tree/0.6.3) - 2016-10-24

## Changed
- Information for new connections is now passed to the server as a map.

## [0.6.2](https://github.com/CrowdHailer/Ace/tree/0.6.2) - 2016-10-24

## Added
- Endpoints can be registered as named processes by passing in a value for the `:name` option.
  Possible values for this are the same as for the underlying `GenServer`.
- The number of servers simultaneously accepting can now be configured.
  Pass an integer value to the `:acceptors` option when starting and endpoint.
  Default value is 50.

## [0.6.1](https://github.com/CrowdHailer/Ace/tree/0.6.1) - 2016-10-17

## Added
- `Ace.TCP.Endpoint.port/1` will return the port an endpoint is listening too.
  Required when the port option is set to `0` and the port is allocated by the OS.

## Fixed
- The `handle_packet` and `handle_info` callbacks for a server module are able produce a return of the format `{:nosend, state}`.

## [0.6.0](https://github.com/CrowdHailer/Ace/tree/0.6.0) - 2016-10-17

## Added
- Collect all processes in an endpoint `GenServer` so that they can be started as a unit and only the endpoint is linked to the calling process. This allows for endpoints to be added to supervision tree.

## Removed
- `Ace.TCP.start/2` use `start_link/2` instead which takes app as the first argument not the second.

## [0.5.2](https://github.com/CrowdHailer/Ace/tree/0.5.2) - 2016-10-13

## Changed
- The governors will keeps starting server processes to match demand.

## [0.5.1](https://github.com/CrowdHailer/Ace/tree/0.5.1) - 2016-10-10

## Changed
- Send any message that is not TCP related to the `handle_info` callback,
  previous only messages that matched `{:data, info}` where handled.

## [0.5.0](https://github.com/CrowdHailer/Ace/tree/0.5.0) - 2016-10-07

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
