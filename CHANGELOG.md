# Change Log
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/)
and this project adheres to [Semantic Versioning](http://semver.org/).

## master

### Added

- `Ace.HTTP.Channel` to encapsulate information about an exchange within the context of a connection.
- `Ace.HTTP.Worker.start_link/2` workers must be started with a channel in addition to application.
- Channel struct is added to the process dictionary of a worker, so socket information is available.

### Removed

- `Ace.HTTP2.Stream.Reset` undocumented internal module.

## [0.16.0](https://github.com/CrowdHailer/Ace/tree/0.16.0) - 2018-04-18

### Changed

- Use `raxx 0.15` which has does not expect query strings to be parsed.  

## [0.15.11](https://github.com/CrowdHailer/Ace/tree/0.15.11) - 2018-03-28

### Added

- `.formatter.exs` file for use with Elixir 1.6+
- `Ace.HTTP1.Parser.parse/2` returns categorized HTTP/2 frame instead of raw frame parts.

### Removed

- `Ace.HTTP1.Parser.parse_from_buffer/2` use `Ace.HTTP1.Parser.parse/2` instead.
- `Ace.HTTP2.Server` undocumented internal module.

## [0.15.10](https://github.com/CrowdHailer/Ace/tree/0.15.10) - 2018-01-20

### Fixed

- Use `GenServer` behaviour in `Ace.HTTP2.Connection` to add default handlers.
- Ensure Endpoint handles its worker dying when sending chunked response.

## [0.15.9](https://github.com/CrowdHailer/Ace/tree/0.15.9) - 2018-01-11

### Added

- `__using__/1` macro to `Ace.HTTP.Service` that defines `start_link` and `child_spec`.

## [0.15.8](https://github.com/CrowdHailer/Ace/tree/0.15.8) - 2018-01-01

### Added

- `Ace.HTTP1.Parser` extracts functionality to incrementally parse data into parts of a Raxx message.
- Server module is checked to implement `Raxx.Server` behaviour when starting a service.
- `Client.stop/1` breaks connection established by a client.
- `Ace.HTTP.Service.child_spec/1` added so services can be added to supervision trees in standard manner.
- `Ace.HTTP.Worker` module added to public api.

### Removed

- `Ace.Governor.Supervisor` is no longer necessary.

### Fixed

- Request has scheme of `:http` when transmitted over `tcp` connection.
- Worker monitors endpoint and will stop when endpoint stops.

## [0.15.7](https://github.com/CrowdHailer/Ace/tree/0.15.7) - 2017-12-28

### Added

- `OPTIONS`, `TRACE` and `CONNECT` method are understood in HTTP/2 requests.


## [0.15.5](https://github.com/CrowdHailer/Ace/tree/0.15.5) - 2017-11-29

### Fixed

- Ensure worker process terminates when complete response is sent.

## [0.15.4](https://github.com/CrowdHailer/Ace/tree/0.15.4) - 2017-11-11

### Added

- HTTP1.Endpoint sends 500 response when worker process crashes.

### Changed

- Use `Logger.debug` to print warning about closing keep-alive connections.


## [0.15.3](https://github.com/CrowdHailer/Ace/tree/0.15.3) - 2017-11-05

### Removed

- No dependency on `HTTPStatus`.

## [0.15.2](https://github.com/CrowdHailer/Ace/tree/0.15.2) - 2017-10-29

### Changed
- Rely on `0.14.x` of raxx.

## [0.15.1](https://github.com/CrowdHailer/Ace/tree/0.15.1) - 2017-10-25

### Fixed
- Server startup logs include port number when serving via cleartext.

## [0.15.0](https://github.com/CrowdHailer/Ace/tree/0.15.0) - 2017-10-16

### Changed
- Rely on `0.13.x` of raxx.

### Removed
- `Ace.HTTP2.Service`, instead use `Ace.HTTP.Service`.

## [0.14.8](https://github.com/CrowdHailer/Ace/tree/0.14.8) - 2017-10-9

### Added
- Upgrade via ALPN to HTTP/2 connections, when using `Ace.HTTP.Service`.

## [0.14.7](https://github.com/CrowdHailer/Ace/tree/0.14.7) - 2017-10-4

### Removed
- `Ace.Application` undocumented internal module
- `Ace.TCP` undocumented internal module
- `Ace.TLS` undocumented internal module
- `Ace.Server` undocumented internal module
- `Ace.Server.Supervisor` undocumented internal module

### Fixed
- Limit forwarded keys to known ssl options only.
- HTTP/2 connection always sends a `Raxx.Trailer` to close a stream with data.

## [0.14.6](https://github.com/CrowdHailer/Ace/tree/0.14.6) - 2017-09-29

### Fixed
- Workers exit normally when client connection is lost prematurely.

## [0.14.5](https://github.com/CrowdHailer/Ace/tree/0.14.5) - 2017-09-28

### Added
- `Ace.HTTP.Service` to communicate with HTTP/1 clients,
  functionality previously provided in `ace_http`.

## [0.14.4](https://github.com/CrowdHailer/Ace/tree/0.14.4) - 2017-09-27

### Fixed
- Stream will not queue data to send that is not a binary.

## [0.14.3](https://github.com/CrowdHailer/Ace/tree/0.14.3) - 2017-09-25

### Fixed
- Fixes made in `0.9.2` and `0.9.3` added to lastest.

## [0.14.2](https://github.com/CrowdHailer/Ace/tree/0.14.2) - 2017-09-19

### Added
- `Ace.HTTP2.ping/2` for checking a connection.

## [0.14.1](https://github.com/CrowdHailer/Ace/tree/0.14.1) - 2017-09-08

### Added
- Client certificate options added to `Ace.HTTP2.Client.start_link`.

## [0.14.0](https://github.com/CrowdHailer/Ace/tree/0.14.0) - 2017-08-31

### Added
- Send any Raxx message using `Ace.HTTP2.send/2`.

### Changed
- Start services with `{hander, config}` instead of `{worker, args}`
- All use of `Ace.Request` has been replaced with `Raxx.Request`.
- All use of `Ace.Response` has been replaced with `Raxx.Response`.

### Removed
- `Ace.Raxx.Handler` all applications are assumed to be raxx applications
- `Ace.HTTP2.Client.send_request/2` use `Ace.HTTP2.send/2`.
- `Ace.HTTP2.Client.send_data/2` use `Ace.HTTP2.send/2`.
- `Ace.HTTP2.Client.send_trailers/2` use `Ace.HTTP2.send/2`.
- `Ace.HTTP2.Server.send_request/2` use `Ace.HTTP2.send/2`.
- `Ace.HTTP2.Server.send_data/2` use `Ace.HTTP2.send/2`.
- `Ace.HTTP2.Server.send_promise/2` use `Ace.HTTP2.send/2`.
- `Ace.HTTP2.Server.send_reset/2` server should exit instead.

## [0.13.1](https://github.com/CrowdHailer/Ace/tree/0.13.1) - 2017-08-26

### Added
- Client can start with `:enable_push` option.
- Client can start with `:max_concurrent_streams` option.
- Server push is only forwarded to client if accepted by client.

### Fixed
- PushPromise frames do not exceed maximum frame size.
- Continuation frames must follow on same stream.

## [0.13.0](https://github.com/CrowdHailer/Ace/tree/0.13.0) - 2017-08-23

### Changed
- Request scheme is atom instead of string.
- Request method is atom instead of string.

## [0.12.1](https://github.com/CrowdHailer/Ace/tree/0.12.1) - 2017-08-22

### Fixed
- Raxx changed from being an optional dependency

## [0.9.3](https://github.com/CrowdHailer/Ace/tree/0.9.3) - 2017-08-20

### Changed
- Discard down messages from unknown monitors.
- Accept request with absolute URL's in request line.

## [0.12.0](https://github.com/CrowdHailer/Ace/tree/0.12.0) - 2017-08-17

### Added
- Client can fetch an idle stream using `Ace.HTTP2.Client.stream/1`.
- Forward stream resets with reason to worker processes.
- `Ace.HTTP2.Client.send_request/2`.
- `Ace.HTTP2.Client.send_trailers/2`.
- `Ace.HTTP2.Server.send_response/2`.
- `Ace.HTTP2.Server.send_reset/2`.
- Inspect protocol implementation for each frame type.

### Changed
- Server receives request object not raw headers.
- Server sends with response object not raw headers.
- Client cannot start a stream with request.
- `Ace.HTTP2.Stream.RaxxHandler` renamed to `Ace.Raxx.Handler`

## [0.9.2](https://github.com/CrowdHailer/Ace/tree/0.9.2) - 2017-08-4

### Fixed
- Governor to correctly demonitor started servers.

## [0.11.1](https://github.com/CrowdHailer/Ace/tree/0.11.1) - 2017-08-03

### Added
- Client for HTTP/2.0.

## [0.11.0](https://github.com/CrowdHailer/Ace/tree/0.11.0) - 2017-08-01

### Added
- Casting for accepted values for each known setting.
- Flow control for outbound data.

### Changed
- Creating priority frame requires exclusive value.

### Fixed
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

### Added
- HTTP/2.0 support via `Ace.HTTP2`

## [0.9.1](https://github.com/CrowdHailer/Ace/tree/0.9.1) - 2017-06-14

### Changed
- Reduced noise from errors of prematurely closed connections.

## [0.9.0](https://github.com/CrowdHailer/Ace/tree/0.9.0) - 2017-04-16

### Changed
- Requires Elixir 1.4 and above,
  required applications are now listed as `extra_applications`.

## [0.8.1](https://github.com/CrowdHailer/Ace/tree/0.8.1) - 2017-04-02

### Added
- Warning logged when application module is not using the `Ace.Application` behaviour.

## [0.8.0](https://github.com/CrowdHailer/Ace/tree/0.8.0) - 2017-03-26

### Added
- `Ace.TLS` for tcp/ssl endpoints, matching `Ace.TCP` function profiles.
- `Ace.Connection` to normalise `:gen_tcp`/`:ssl` interfaces.
- Governors can be throttled to zero to drain connections,
  see `Ace.Governor.Supervisor.drain/1`

### Changed
- New connection calls `handle_connect/2` not `init/2`
- Connection lost calls `handle_disconnect/2` not `terminate/2`
- `Ace.TCP` is now the callback module when starting and endpoint,
  there is no `Ace.TCP.Endpoint` module anymore.
- `Ace.Governor` now a `GenServer` to handle OTP sys calls

### Removed
- `Ace.TCP.Server`, now `Ace.Server`.
- `Ace.TCP.Server.Supervisor`, now `Ace.Server.Supervisor`.
- `Ace.TCP.Governor`, now `Ace.Governor`.
- `Ace.TCP.Governor.Supervisor`, now `Ace.Governor.Supervisor`.

## [0.7.1](https://github.com/CrowdHailer/Ace/tree/0.7.1) - 2017-02-13

### Changed
- Startup information is printed using `Logger` and not directly `IO`.

### Fixed
- Remove warnings about bracket use from Elixir 1.4.

## [0.7.0](https://github.com/CrowdHailer/Ace/tree/0.7.0) - 2016-10-26

### Added
- Support a response with a timeout from server modules.
  Passed directly to GenServer so integer and `:hibernate` responses are supported.
- Support closing the connection from the server side.
  It is best to reserver server side closing for misbehaving connections.
- Added callbacks to `Ace.TCP.Server` so that is can be included as a behaviour.

## [0.6.3](https://github.com/CrowdHailer/Ace/tree/0.6.3) - 2016-10-24

### Changed
- Information for new connections is now passed to the server as a map.

## [0.6.2](https://github.com/CrowdHailer/Ace/tree/0.6.2) - 2016-10-24

### Added
- Endpoints can be registered as named processes by passing in a value for the `:name` option.
  Possible values for this are the same as for the underlying `GenServer`.
- The number of servers simultaneously accepting can now be configured.
  Pass an integer value to the `:acceptors` option when starting and endpoint.
  Default value is 50.

## [0.6.1](https://github.com/CrowdHailer/Ace/tree/0.6.1) - 2016-10-17

### Added
- `Ace.TCP.Endpoint.port/1` will return the port an endpoint is listening too.
  Required when the port option is set to `0` and the port is allocated by the OS.

### Fixed
- The `handle_packet` and `handle_info` callbacks for a server module are able produce a return of the format `{:nosend, state}`.

## [0.6.0](https://github.com/CrowdHailer/Ace/tree/0.6.0) - 2016-10-17

### Added
- Collect all processes in an endpoint `GenServer` so that they can be started as a unit and only the endpoint is linked to the calling process. This allows for endpoints to be added to supervision tree.

### Removed
- `Ace.TCP.start/2` use `start_link/2` instead which takes app as the first argument not the second.

## [0.5.2](https://github.com/CrowdHailer/Ace/tree/0.5.2) - 2016-10-13

### Changed
- The governors will keeps starting server processes to match demand.

## [0.5.1](https://github.com/CrowdHailer/Ace/tree/0.5.1) - 2016-10-10

### Changed
- Send any message that is not TCP related to the `handle_info` callback,
  previous only messages that matched `{:data, info}` where handled.

## [0.5.0](https://github.com/CrowdHailer/Ace/tree/0.5.0) - 2016-10-07

### Added
- How to hande a tcp connection is specified by an application server module.

## [0.4.0](https://github.com/CrowdHailer/Ace/tree/0.4.0) - 2016-10-06

### Added
- System sends welcome message.
- System sends data messages over the socket.

### Changed
- Starting a server no longer blocks until the connection has been closed.

## [0.3.0](https://github.com/CrowdHailer/Ace/tree/0.3.0) - 2016-10-04

### Added
- Dialyzer for static analysis, with updated contributing instructions.

### Changed
- Nothing, only bumped version due to incorrect publishing on hex.

## [0.2.0](https://github.com/CrowdHailer/Ace/tree/0.2.0) - 2016-10-04

### Added
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
