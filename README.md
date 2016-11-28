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

##Setup
In order to use this in your program, you must install the
[picohttpparser.h](https://github.com/h2o/picohttpparser/blob/master/picohttpparser.h)
header on your machine, and link your Nim program with
[picohttpparser.c](https://github.com/h2o/picohttpparser/blob/master/picohttpparser.c).

The easiest way to do this is to:

1. Copy the [picohttpparser](https://github.com/h2o/picohttpparser) sources into your
   project sources,
2. Use the [cincludes](http://nim-lang.org/docs/nimc.html) Nim compiler flag
   to add the picohttpparser sources to the C compiler include search path,
3. And create a Nim file that uses the
   [compile pragma](http://nim-lang.org/docs/manual.html#implementation-specific-pragmas-compile-pragma)
   to compile
   [picohttpparser.c](https://github.com/h2o/picohttpparser/blob/master/picohttpparser.c).

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
