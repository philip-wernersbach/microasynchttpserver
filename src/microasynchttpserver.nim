# microasynchttpserver.nim
# Part of microasynchttpserver by
# Philip Wernersbach <philip.wernersbach@gmail.com>
#
# The MIT License (MIT)
#
# Copyright (c) 2016 Philip Wernersbach
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

import std/[asyncdispatch, asyncnet, asynchttpserver, strutils, uri, options, strformat, selectors]

import picohttpparser/api

const HTTP_HEADER_BUFFER_INITIAL_SIZE = 512

type MicroAsyncHttpServer* = ref object
    ## A MicroAsyncHttpServer object.
    ## It is API-compatible with AsyncHttpServer.

    socket: AsyncSocket

proc newMicroAsyncHttpServer*(): MicroAsyncHttpServer =
    ## Creates a new MicroAsyncHttpServer instance

    return MicroAsyncHttpServer(socket: newAsyncSocket())

const badRequestHttpResponse = "HTTP/1.0 400 Bad Request\r\nExpires: Thu, 01 Jan 1970 00:00:01 GMT\r\nContent-Length: 0\r\n\r\n"
    ## The 400 Bad Request HTTP response string used by MicroAsyncHttpServer

proc sendBadRequestAndClose(socket: AsyncSocket): Future[void] {.async.} =
    if not socket.isClosed:
        await socket.send(badRequestHttpResponse)
        socket.close()

proc processConnection(socket: AsyncSocket, hostname: string, callback: proc (request: Request): Future[void] {.closure,gcsafe.}) {.async.} =
    while not socket.isClosed:
        var httpMethod: string
        var path: string
        var minorVersion: cint

        var numberOfHeaders = 0
        var headerBuffer = newStringOfCap(HTTP_HEADER_BUFFER_INITIAL_SIZE)

        while true:
            let line = await socket.recvLine()

            if line == "":
                if not socket.isClosed:
                    socket.close()

                return

            if not (((line.len == 1) and (line[0] == char(0x0a))) or ((line.len == 2) and (line[0] == char(0x0d)) and (line[1] == char(0x0a)))):
                numberOfHeaders += 1

                headerBuffer.add(line)
                headerBuffer.add("\n")
            else:
                headerBuffer.add("\n")
                break

        var headers = newSeq[phr_header](numberOfHeaders)
        
        if tryParseRequest(headerBuffer, httpMethod, path, minorVersion, headers) < 0:
            await socket.sendBadRequestAndClose()
            return
        
        var reqMethodIsValid = true

        let reqMethod = case httpMethod.toUpper
            of "GET":
                HttpGet
            of "POST":
                HttpPost
            of "HEAD":
                HttpHead
            of "PUT":
                HttpPut
            of "DELETE":
                HttpDelete
            of "TRACE":
                HttpTrace
            of "OPTIONS":
                HttpOptions
            of "CONNECT":
                HttpConnect
            of "PATCH":
                HttpPatch
            else:
                reqMethodIsValid = false
                HttpGet

        if not reqMethodIsValid:
            await socket.sendBadRequestAndClose()
            return
        
        try:
            await callback(Request(
                client: socket,
                reqMethod: reqMethod,
                headers: headers,
                protocol: (orig: "HTTP/1." & $minorVersion, major: 1, minor: int(minorVersion)),
                url: parseUri(path), hostname: hostname, body: ""
            ))
        except ValueError:
            await socket.sendBadRequestAndClose()

proc serve*(
    server: MicroAsyncHttpServer,
    port: Port,
    callback: proc (request: Request): Future[void] {.closure,gcsafe.},
    address = "127.0.0.1",
    sockOpts: set[SOBool] = {OptReuseAddr},
) {.async.} =
    ## Starts the server on the specified port and address.
    ## 
    ## The `callback` argument is the callback that will be run for each request.
    ## You cannot assume that your response will be sent or handled correctly once the callback returns.
    ## For this reason, you must make sure your callback does not return until you want the client to disconnect or get a response back.
    ## 
    ## To set socket options, use the `sockOpts` argument.
    ## By default it is set to {OptReuseAddr}.
    ## If you want to use multiple instances to serve over multiple threads, you should also add OptReusePort.

    for opt in sockOpts:
        server.socket.setSockOpt(opt, true)

    server.socket.bindAddr(port, address)
    server.socket.listen()

    while true:
        var socket: tuple[address: string, client: AsyncSocket]
        try:
            # Trying to re-implement the accept proc from asyncnet turned out to not work.
            # All sorts of issues were going on that ultimately would mess up the server's operation, including double-completion of futures.
            # Currently this try-except is the best way to avoid crashing the server on file descriptor exhaustion.
            # The only caveat is that connections that cannot be served will be immediately rejected instead of waiting in some cases.
            socket = await server.socket.acceptAddr()
        except IOSelectorsException:
            # The socket couldn't be accepted right now, restart at the beginning of the loop
            continue

        try:
            asyncCheck socket.client.processConnection(socket.address, callback)
        except CatchableError:
            if not socket.client.isClosed:
                socket.client.close()

            let e = getCurrentException()
            stderr.write(e.getStackTrace())
            stderr.write("Error: unhandled exception: ")
            stderr.writeLine(getCurrentExceptionMsg())

proc readBody*(req: Request): Future[Option[string]] {.async.} =
    ## Reads the request body and returns it.
    ## 
    ## The proc will return None if no body was read.
    ## If the request cannot have a body (GET or HEAD request, no Content-Length header, etc), the proc will return None without having done anything.
    ## For this reason, you shouldn't need to perform these checks before calling it, since it will require the computer to do duplicate work.
    ## 
    ## If the client disconnected before the full body was read, OSError will be raised.
    ## 
    ## Note that this proc does *not* set the `Request`'s `body` field.

    # GET and HEAD requests cannot have a body
    if req.reqMethod in {HttpGet, HttpHead}:
        return none[string]()
    
    # Requests without a Content-Length header cannot have a body
    if not req.headers.hasKey("Content-Length"):
        return none[string]()

    let bodyLen = req.headers["Content-Length"].parseInt()
    var bodyReadPos = 0

    # Preallocate body size
    var body = newString(bodyLen)

    var buf: array[1024, char]

    while true:
        # Read buffer
        let bufLen = await req.client.recvInto(addr buf, min(bodyLen - bodyReadPos, buf.len))

        # End of stream; break
        if bufLen == 0:
            break

        # Write read buffer to body
        copyMem(addr body[bodyReadPos], addr buf[0], bufLen)

        bodyReadPos += bufLen

        # The whole body was read; break
        if bodyReadPos >= bodyLen:
            break

    # If the body read position is less than the expected size, the client must have disconnected part-way through the read.
    # In that case, we'll free the memory that we've allocated, close the socket, and finally raise OSError.
    if bodyReadPos < bodyLen:
        body = ""
        if not req.client.isClosed:
            req.client.close()

        raise newException(EOFError, fmt"Client disconnected before full body could be read ({bodyReadPos}/{bodyLen} bytes read)")

    # If we didn't return yet, the body was fully read
    return some body
