//===----------------------------------------------------------------------===//
//
// This source file is part of the AWSSDKSwift open source project
//
// Copyright (c) 2017-2020 the AWSSDKSwift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of AWSSDKSwift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import AsyncHTTPClient
import NIO
import XCTest
@testable import AWSSDKSwiftCore

class PaginateTests: XCTestCase {
    enum Error: Swift.Error {
        case didntFindToken
    }
    var awsServer: AWSTestServer!
    var eventLoopGroup: EventLoopGroup!
    var httpClient: AWSHTTPClient!
    var client: AWSClient!

    override func setUp() {
        // create server and client
        awsServer = AWSTestServer(serviceProtocol: .json)
        eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 3)
        httpClient = AsyncHTTPClient.HTTPClient(eventLoopGroupProvider: .shared(eventLoopGroup))
        client = AWSClient(
            accessKeyId: "",
            secretAccessKey: "",
            region: .useast1,
            service:"TestClient",
            serviceProtocol: .json(version: "1.1"),
            apiVersion: "2020-01-21",
            endpoint: "http://localhost:\(awsServer.serverPort)",
            middlewares: [AWSLoggingMiddleware()],
            httpClientProvider: .shared(httpClient)
        )
    }

    override func tearDown() {
        XCTAssertNoThrow(try self.awsServer.stop())
        XCTAssertNoThrow(try self.httpClient.syncShutdown())
        XCTAssertNoThrow(try self.eventLoopGroup.syncShutdownGracefully())
    }

    // test structures/functions
    struct CounterInput: AWSEncodableShape, AWSPaginateToken, Decodable {
        let inputToken: Int?
        let pageSize: Int

        init(inputToken: Int?, pageSize: Int) {
            self.inputToken = inputToken
            self.pageSize = pageSize
        }

        func usingPaginationToken(_ token: Int) -> CounterInput {
            return .init(inputToken: token, pageSize: self.pageSize)
        }
    }
    // conform to Encodable so server can encode these
    struct CounterOutput: AWSDecodableShape, Encodable {
        let array: [Int]
        let outputToken: Int?
    }

    func counter(_ input: CounterInput, on eventLoop: EventLoop?) -> EventLoopFuture<CounterOutput> {
        return client.send(operation: "TestOperation", path: "/", httpMethod: "POST", input: input, on: eventLoop)
    }

    func counterPaginator(_ input: CounterInput, onPage: @escaping (CounterOutput, EventLoop)->EventLoopFuture<Bool>) -> EventLoopFuture<Void> {
        return client.paginate(input: input, command: counter, tokenKey: \CounterOutput.outputToken, onPage: onPage)
    }

    func testIntegerTokenPaginate() throws {

        // paginate input
        var finalArray: [Int] = []
        let input = CounterInput(inputToken: nil, pageSize: 4)
        let future = counterPaginator(input) { result, eventloop in
            // collate results into array
            finalArray.append(contentsOf: result.array)
            return eventloop.makeSucceededFuture(true)
        }

        let arraySize = 23
        do {
            // aws server process
            try awsServer.process { (input: CounterInput) throws -> AWSTestServer.Result<CounterOutput> in
                // send part of array of numbers based on input startIndex and pageSize
                let startIndex = input.inputToken ?? 0
                let endIndex = min(startIndex+input.pageSize, arraySize)
                var array: [Int] = []
                for i in startIndex..<endIndex {
                    array.append(i)
                }
                let continueProcessing = (endIndex != arraySize)
                let output = CounterOutput(array: array, outputToken: endIndex != arraySize ? endIndex : nil)
                return AWSTestServer.Result(output: output, continueProcessing: continueProcessing)
            }

            // wait for response
            try future.wait()
        } catch {
            print(error)
        }

        // verify contents of array
        XCTAssertEqual(finalArray.count, arraySize)
        for i in 0..<finalArray.count {
            XCTAssertEqual(finalArray[i], i)
        }
    }

    // test structures/functions
    struct StringListInput: AWSEncodableShape, AWSPaginateToken, Decodable {
        let inputToken: String?
        let pageSize: Int

        init(inputToken: String?, pageSize: Int) {
            self.inputToken = inputToken
            self.pageSize = pageSize
        }

        func usingPaginationToken(_ token: String) -> StringListInput {
            return .init(inputToken: token, pageSize: self.pageSize)
        }
    }
    // conform to Encodable so server can encode these
    struct StringListOutput: AWSDecodableShape, Encodable {
        let array: [String]
        let outputToken: String?
    }

    func stringList(_ input: StringListInput, on eventLoop: EventLoop? = nil) -> EventLoopFuture<StringListOutput> {
        return client.send(operation: "TestOperation", path: "/", httpMethod: "POST", input: input, on: eventLoop)
    }

    func stringListPaginator(_ input: StringListInput, on eventLoop: EventLoop? = nil, onPage: @escaping (StringListOutput, EventLoop)->EventLoopFuture<Bool>) -> EventLoopFuture<Void> {
        return client.paginate(input: input, command: stringList, tokenKey: \StringListOutput.outputToken, on: eventLoop, onPage: onPage)
    }

    // create list of unique strings
    let stringList = Set("Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.".split(separator: " ").map {String($0)}).map {$0}

    func stringListServerProcess(_ input: StringListInput) throws -> AWSTestServer.Result<StringListOutput> {
        // send part of array of numbers based on input startIndex and pageSize
        var startIndex = 0
        if let inputToken = input.inputToken {
            guard let stringIndex = stringList.firstIndex(of:inputToken) else { throw Error.didntFindToken }
            startIndex = stringIndex
        }
        let endIndex = min(startIndex+input.pageSize, stringList.count)
        var array: [String] = []
        for i in startIndex..<endIndex {
            array.append(stringList[i])
        }
        var outputToken: String? = nil
        var continueProcessing = false
        if endIndex < stringList.count {
            outputToken = stringList[endIndex]
            continueProcessing = true
        }
        let output = StringListOutput(array: array, outputToken: outputToken)
        return AWSTestServer.Result(output: output, continueProcessing: continueProcessing)
    }

    func testStringTokenPaginate() throws {

        // paginate input
        var finalArray: [String] = []
        let input = StringListInput(inputToken: nil, pageSize: 5)
        let future = stringListPaginator(input) { result, eventloop in
            // collate results into array
            finalArray.append(contentsOf: result.array)
            return eventloop.makeSucceededFuture(true)
        }

        do {
            // aws server process
            try awsServer.process(stringListServerProcess)

            // wait for response
            try future.wait()
        } catch {
            print(error)
        }

        // verify contents of array
        XCTAssertEqual(finalArray.count, stringList.count)
        for i in 0..<finalArray.count {
            XCTAssertEqual(finalArray[i], stringList[i])
        }
    }

    struct ErrorOutput: AWSShape {
        let error: String
    }

    func testPaginateError() throws {

        // paginate input
        let input = StringListInput(inputToken: nil, pageSize: 5)
        let future = stringListPaginator(input) { _,eventloop in
            return eventloop.makeSucceededFuture(true)
        }

        do {
            // aws server process
            let error = AWSTestServer.ErrorType(status: 400, errorCode:"InvalidAction", message: "You didn't mean that")
            try awsServer.processWithErrors(stringListServerProcess, errors: { _ in AWSTestServer.Result(output: error, continueProcessing: false)})

            // wait for response
            try future.wait()

            XCTFail("testPaginateError: should have errored")
        } catch {
            print(error)
        }
    }

    func testPaginateErrorAfterFirstRequest() throws {

        // paginate input
        let input = StringListInput(inputToken: nil, pageSize: 5)
        let future = stringListPaginator(input) { _,eventloop in
            return eventloop.makeSucceededFuture(true)
        }

        do {
            // aws server process
            let error = AWSTestServer.ErrorType(status: 400, errorCode:"InvalidAction", message: "You didn't mean that")
            try awsServer.processWithErrors(stringListServerProcess, errors: {count in
                if count > 0 {
                    return AWSTestServer.Result(output: error, continueProcessing: false)
                } else {
                    return AWSTestServer.Result(output: nil, continueProcessing: true)
                }
            })

            // wait for response
            try future.wait()

            XCTFail("testPaginateError: should have errored")
        } catch {
            print(error)
        }
    }

    func testPaginateEventLoop() throws {
        // paginate input
        let clientEventLoop = client.eventLoopGroup.next()
        let input = StringListInput(inputToken: nil, pageSize: 5)
        let future = stringListPaginator(input, on: clientEventLoop) { _,eventloop in
            XCTAssertTrue(clientEventLoop.inEventLoop)
            XCTAssertTrue(clientEventLoop === eventloop)
            return eventloop.makeSucceededFuture(true)
        }

        do {
            // aws server process
            try awsServer.process(stringListServerProcess)

            // wait for response
            try future.wait()
        } catch {
            print(error)
        }
    }
}
