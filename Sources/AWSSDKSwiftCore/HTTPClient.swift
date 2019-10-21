//
//  HTTPClient.swift
//  AWSSDKSwiftCore
//
//  Created by Joseph Mehdi Smith on 4/21/18.
//
// Informed by Vapor's HTTP client
// https://github.com/vapor/http/tree/master/Sources/HTTPKit/Client
// and the swift-server's swift-nio-http-client
// https://github.com/swift-server/swift-nio-http-client
//

import NIO
import NIOHTTP1
import NIOSSL
import NIOFoundationCompat
import Foundation

/// HTTP Client class providing API for sending HTTP requests
public final class HTTPClient {

    /// Request structure to send
    public struct Request {
        var head: HTTPRequestHead
        var body: Data = Data()
    }

    /// Response structure received back
    public struct Response {
        let head: HTTPResponseHead
        let body: Data

        public func contentType() -> String? {
            return head.headers.filter { $0.name.lowercased() == "content-type" }.first?.value
        }
    }

    /// Errors returned from HTTPClient when parsing responses
    public enum HTTPError: Error {
        case malformedHead, malformedBody, malformedURL
    }

    private let hostname: String
    private let headerHostname: String
    private let port: Int
    private let eventGroup: EventLoopGroup

    public init(url: URL,
                eventGroup: EventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)) throws {
        guard let scheme = url.scheme else {
            throw HTTPClient.HTTPError.malformedURL
        }
        guard let hostname = url.host else {
            throw HTTPClient.HTTPError.malformedURL
        }

        self.hostname = hostname

        if let port = url.port {
            self.port = port
            self.headerHostname = "\(hostname):\(port)"
        } else {
            let isSecure = (scheme == "https")
            self.port = isSecure ? 443 : 80
            self.headerHostname = hostname
        }

        self.eventGroup = eventGroup
    }

    public init(hostname: String,
                port: Int,
                eventGroup: EventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)) {
        self.headerHostname = hostname
        self.hostname = String(hostname.split(separator:":")[0])
        self.port = port
        self.eventGroup = eventGroup
    }

    /// add SSL Handler to channel pipeline if the port is 443
    func addSSLHandlerIfNeeded(_ pipeline : ChannelPipeline, hostname: String, port: Int) -> EventLoopFuture<Void> {
        if (port == 443) {
            do {
                let tlsConfiguration = TLSConfiguration.forClient()
                let sslContext = try NIOSSLContext(configuration: tlsConfiguration)
                let tlsHandler = try NIOSSLClientHandler(context: sslContext, serverHostname: hostname)
                return pipeline.addHandler(tlsHandler, position:.first)
            } catch {
                return pipeline.eventLoop.makeFailedFuture(error)
            }
        }
        return pipeline.eventLoop.makeSucceededFuture(())
    }

    /// send request to HTTP client, return a future holding the Response
    public func connect(_ request: Request) -> EventLoopFuture<Response> {
        let response: EventLoopPromise<Response> = eventGroup.next().makePromise()

        _ = ClientBootstrap(group: self.eventGroup)
            .connectTimeout(TimeAmount.seconds(5))
            .channelOption(ChannelOptions.socket(SocketOptionLevel(IPPROTO_TCP), TCP_NODELAY), value: 1)
            .channelInitializer { channel in
                return channel.pipeline.addHTTPClientHandlers()
                    .flatMap {
                        return self.addSSLHandlerIfNeeded(channel.pipeline, hostname: self.hostname, port: self.port)
                    }
                    .flatMap {
                        let handlers : [ChannelHandler] = [
                            HTTPClientRequestSerializer(hostname: self.headerHostname),
                            HTTPClientResponseHandler(promise: response)
                        ]
                        return channel.pipeline.addHandlers(handlers)
                }
            }
            .connect(host: hostname, port: port)
            .flatMap { channel -> EventLoopFuture<Void> in
                return channel.writeAndFlush(request)
            }
            .whenFailure { error in
                response.fail(error)
        }
        return response.futureResult
    }

    public func close(_ callback: @escaping (Error?) -> Void) {
        eventGroup.shutdownGracefully(callback)
    }

    /// Channel Handler for serializing request header and data
    private class HTTPClientRequestSerializer : ChannelOutboundHandler {
        typealias OutboundIn = Request
        typealias OutboundOut = HTTPClientRequestPart

        private let hostname: String

        init(hostname: String) {
            self.hostname = hostname
        }

        func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
            let request = unwrapOutboundIn(data)
            var head = request.head

            head.headers.replaceOrAdd(name: "Host", value: hostname)
            head.headers.replaceOrAdd(name: "User-Agent", value: "AWS SDK Swift Core")
            head.headers.replaceOrAdd(name: "Accept", value: "*/*")
            head.headers.replaceOrAdd(name: "Content-Length", value: request.body.count.description)
            // TODO implement keep-alive
            head.headers.replaceOrAdd(name: "Connection", value: "Close")


            context.write(wrapOutboundOut(.head(head)), promise: nil)
            if request.body.count > 0 {
                var buffer = ByteBufferAllocator().buffer(capacity: request.body.count)
                buffer.writeBytes(request.body)
                context.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
            }
            context.write(self.wrapOutboundOut(.end(nil)), promise: promise)
        }
    }

    /// Channel Handler for parsing response from server
    private class HTTPClientResponseHandler: ChannelInboundHandler {
        typealias InboundIn = HTTPClientResponsePart
        typealias OutboundOut = Response

        private enum ResponseState {
            /// Waiting to parse the next response.
            case ready
            /// Currently parsing the response's body.
            case parsingBody(HTTPResponseHead, Data?)
        }

        private var state: ResponseState = .ready
        private let promise : EventLoopPromise<Response>

        init(promise: EventLoopPromise<Response>) {
            self.promise = promise
        }

        func errorCaught(context: ChannelHandlerContext, error: Error) {
            context.fireErrorCaught(error)
        }

        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            switch unwrapInboundIn(data) {
            case .head(let head):
                switch state {
                case .ready: state = .parsingBody(head, nil)
                case .parsingBody: promise.fail(HTTPClient.HTTPError.malformedHead)
                }
            case .body(var body):
                switch state {
                case .ready: promise.fail(HTTPClient.HTTPError.malformedBody)
                case .parsingBody(let head, let existingData):
                    let data: Data
                    if var existing = existingData {
                        existing += body.readData(length: body.readableBytes) ?? Data()
                        data = existing
                    } else {
                        data = body.readData(length: body.readableBytes) ?? Data()
                    }
                    state = .parsingBody(head, data)
                }
            case .end(let tailHeaders):
                assert(tailHeaders == nil, "Unexpected tail headers")
                switch state {
                case .ready: promise.fail(HTTPClient.HTTPError.malformedHead)
                case .parsingBody(let head, let data):
                    let res = Response(head: head, body: data ?? Data())
                    if context.channel.isActive {
                        context.fireChannelRead(wrapOutboundOut(res))
                    }
                    promise.succeed(res)
                    state = .ready
                }
            }
        }
    }
}
