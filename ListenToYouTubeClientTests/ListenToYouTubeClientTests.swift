//
//  ListenToYouTubeClientTests.swift
//  ListenToYouTubeClientTests
//
//  Created by Miles Hollingsworth on 6/28/16.
//  Copyright © 2016 Miles Hollingsworth. All rights reserved.
//

import XCTest
@testable import ListenToYouTubeClient
import ReactiveCocoa

class ListenToYouTubeClientTests: XCTestCase {
    func testSuccess() {
        let expectation = expectationWithDescription("wait")
        
        ListenToYouTubeClient.sharedClient.audioStreamProducer(NSURL(string: "https://www.youtube.com/watch?v=Lx_wbGNh2zU")!).startWithResult { result in
            switch result {
            case .Success(let status):
                switch status {
                case .Success:
                    expectation.fulfill()
                    
                default:
                    break
                }
                
                print(status)
                
            case .Failure(let error):
                print(error)
            }
            
        }
        
        waitForExpectationsWithTimeout(40.0) { (error) in
            print(error)
        }
    }
}
