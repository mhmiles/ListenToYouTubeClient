//
//  ListenToYouTubeClientTests.swift
//  ListenToYouTubeClientTests
//
//  Created by Miles Hollingsworth on 6/28/16.
//  Copyright © 2016 Miles Hollingsworth. All rights reserved.
//

import XCTest
@testable import ListenToYouTubeClient
import ReactiveSwift

class ListenToYouTubeClientTests: XCTestCase {
    func testSuccess() {
        let timeout = expectation(description: "wait")
        
        ListenToYouTubeClient.shared.audioStreamProducer(URL(string: "https://www.youtube.com/watch?v=Lx_wbGNh2zU")! as URL).startWithResult { result in
            switch result {
            case .success(let status):
                switch status {
                case .success:
                    timeout.fulfill()
                    
                default:
                    break
                }
                
                print(status)
                
            case .failure(let error):
                print(error)
            }
            
        }
        
        waitForExpectations(timeout: 60.0) { (error) in
            print(error)
        }
    }
    
    func testFailure() {
                let timeout = expectation(description: "wait")
        
        ListenToYouTubeClient.shared.audioStreamProducer(URL(string: "abcd")!).startWithResult { result in
            switch result {
            case .success(let status):
                switch status {
                case .success:
                    timeout.fulfill()
                    
                default:
                    break
                }
                
                print(status)
                
            case .failure(let error):
                print(error)
                timeout.fulfill()
            }
            
        }
        
        waitForExpectations(timeout: 60.0) { (error) in
            print(error)
        }
    }
}
