# microasynchttpserver
microasynchttpserver is a thin asynchronous HTTP server library for Nim. It is
API compatible with Nim's built-in
[asynchttpserver](https://github.com/nim-lang/Nim/blob/devel/lib/pure/asynchttpserver.nim),
and allows programs greater control over the HTTP connection than
asynchttpserver does.

##Features
* Production-ready
* Uses
  [nim-picohttpparser](https://github.com/philip-wernersbach/nim-picohttpparser)
  for HTTP header parsing
* Acts as a thin HTTP server library
    * Only parses HTTP method, protocol version, URL, and headers
    * Everything else is up to the application

##Usage
microasynchttpserver is mostly API compatible with
[asynchttpserver](https://github.com/nim-lang/Nim/blob/devel/lib/pure/asynchttpserver.nim).
Use the `newMicroAsyncHttpServer` proc to instantiate a `MicroAsyncHttpServer`,
and use it just like an `AsyncHttpServer`.

`MicroAsyncHttpServer` will only fill in the `client`, `reqMethod`, `headers`,
`protocol`, `url`, and `hostname` fields of `Request` objects. HTTP request
bodies/data must be handled by your application, and read directly from the
`client` socket.

##License
This project is licensed under the MIT License. For full license text, see
[`LICENSE`](LICENSE).
