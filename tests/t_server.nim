import std/[unittest, asynchttpserver, asyncdispatch, strutils, httpclient, options]

import microasynchttpserver

test "Accept GET and POST":
    proc main() {.async.} =
        let server = newMicroAsyncHttpServer()

        proc onRequest(req: Request) {.closure, async.} =
            let body = (await req.readBody()).get("")

            await req.respond(Http200, body)

        const serverAddr = "127.0.0.1"
        const serverPort = 8989

        asyncCheck server.serve(serverPort.Port, serverAddr, onRequest)

        let client = newAsyncHttpClient()

        const serverUrl = "http://" & serverAddr & ":" & $serverPort

        # Do a GET (no body)
        let noBodyRes = await client.getContent(serverUrl)

        require(noBodyRes == "")

        # Do a POST with a body
        const bodyContent = "abc"
        let bodyRes = await client.postContent(serverUrl, body = bodyContent)

        require(bodyRes == bodyContent)

    waitFor main()
