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

import asyncdispatch
import asyncnet
import asynchttpserver
import strutils
import uri

import picohttpparser_api

const HTTP_HEADER_BUFFER_INITIAL_SIZE = 512

type
    MicroAsyncHttpServer* = ref tuple
        socket: AsyncSocket

proc newMicroAsyncHttpServer*(): MicroAsyncHttpServer =
    new(result)
    result.socket = newAsyncSocket()

proc sendBadRequestAndClose(socket: AsyncSocket): Future[void] {.async.} =
    if not socket.isClosed:
        await socket.send("HTTP/1.0 400 Bad Request\r\nExpires: Thu, 01 Jan 1970 00:00:01 GMT\r\nContent-Length: 0\r\n\r\n")
        socket.close

proc processConnection(socket: AsyncSocket, hostname: string, callback: proc (request: Request): Future[void] {.closure,gcsafe.}) {.async.} =
    while not socket.isClosed:
        var httpMethod: string
        var path: string
        var minorVersion: cint

        var numberOfHeaders = 0
        var headerBuffer = newStringOfCap(HTTP_HEADER_BUFFER_INITIAL_SIZE)

        while true:
            let line = await socket.recvLine

            if line == "":
                if not socket.isClosed:
                    socket.close

                return

            if not (((line.len == 1) and (line[0] == char(0x0a))) or ((line.len == 2) and (line[0] == char(0x0d)) and (line[1] == char(0x0a)))):
                numberOfHeaders += 1

                headerBuffer.add(line)
                headerBuffer.add("\n")
            else:
                headerBuffer.add("\n")
                break

        var headers = newSeq[phr_header](numberOfHeaders)
        
        if tryParseRequest(headerBuffer, httpMethod, path, minorVersion, headers) >= 0:
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

            if reqMethodIsValid:
                var requestIsValid = true
                var request: Request

                try:
                    request = Request(client: socket, reqMethod: reqMethod, headers: headers,
                                          protocol: (orig: "HTTP/1." & $minorVersion, major: 1, minor: int(minorVersion)), 
                                          url: parseUri(path), hostname: hostname, body: "")
                except ValueError:
                    requestIsValid = false

                if requestIsValid:
                    await callback(request)
                else:
                    await socket.sendBadRequestAndClose
            else:
                await socket.sendBadRequestAndClose
        else:
            await socket.sendBadRequestAndClose

proc serve*(server: MicroAsyncHttpServer, port: Port, callback: proc (request: Request): Future[void] {.closure,gcsafe.},
            address = "") {.async.} =

    server.socket.setSockOpt(OptReuseAddr, true)
    server.socket.bindAddr(port, address)
    server.socket.listen

    while true:
        let socket = await server.socket.acceptAddr

        try:
            asyncCheck socket.client.processConnection(socket.address, callback)
        except Exception:
            if not socket.client.isClosed:
                socket.client.close

            let e = getCurrentException()
            stderr.write(e.getStackTrace())
            stderr.write("Error: unhandled exception: ")
            stderr.writeLine(getCurrentExceptionMsg())
