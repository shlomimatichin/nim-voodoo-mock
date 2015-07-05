import asyncdispatch
import asyncnet
import logging
import json

type
    Callback = proc(json: var JsonNode): JsonNode
    IPCServer* = ref object
        callback: Callback
        socket: AsyncSocket

proc close*(self: var IPCServer) =
    if self == nil:
        return
    if self.socket == nil:
        return
    self.socket.close()
    self.socket = nil

proc serveConnectionHeader(self: var IPCServer, connection: AsyncSocket) =
    var server = self
    var future = connection.recv(sizeof(uint32))
    future.callback = proc() =
        if future.error != nil:
            error("Error receiving header: " & future.error.msg)
            connection.close()
            return
        if future.read.len == 0:
            connection.close()
            return
        if future.read.len != sizeof(uint32):
            error("Partial header received")
            connection.close()
            return
        var header = future.read
        var length = cast[ptr uint32](header[0].addr)[].int
        var future2 = connection.recv(length)
        future2.callback = proc() =
            if future2.error != nil:
                error("Error receiving data: " & future2.error.msg)
                connection.close()
                return
            if future2.read.len != length:
                error("Partial data received. Expected $1 was $2", length, future2.read.len)
                connection.close()
                return
            var json = parseJson(future2.read)
            var response: JsonNode
            try:
                response = server.callback(json)
            except:
                error("Error handling command: $1 error: $2 stack: $3",
                    future2.read, getCurrentExceptionMsg(), getStackTrace(getCurrentException()))
                response = %*{"status": "error", "message": getCurrentExceptionMsg()}
            var serialized = $response
            var responseHeader = newString(sizeof(uint32))
            cast[ptr uint32](responseHeader[0].addr)[] = serialized.len.uint32
            var future3 = connection.send(responseHeader & serialized)
            future3.callback = proc() =
                if future3.error != nil:
                    error("Error sending data: " & future3.error.msg)
                    connection.close()
                    return
            serveConnectionHeader(server, connection)

proc serve(self: var IPCServer) =
    var server = self
    var future = self.socket.accept()
    future.callback = proc() =
        if future.error != nil:
            error("Error serving IPC: " & future.error.msg)
            return
        serveConnectionHeader(server, future.read)
        serve(server)

proc newIPCServer*(port: int, callback: Callback): IPCServer =
    result = IPCServer(callback: callback)
    result.socket = newAsyncSocket()
    result.socket.setSockOpt(OptReuseAddr, true)
    result.socket.bindAddr(Port(port))
    result.socket.listen(10)
    serve(result)
