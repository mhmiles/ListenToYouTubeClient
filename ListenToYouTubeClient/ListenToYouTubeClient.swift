//
//  ListenToYouTubeClient.swift
//  ListenToYouTubeClient
//
//  Created by Miles Hollingsworth on 6/28/16.
//  Copyright © 2016 Miles Hollingsworth. All rights reserved.
//

import Foundation
import ReactiveSwift
import Alamofire
import JavaScriptCore

private let baseURL = URL(string: "http://www.listentoyoutube.com")!

public struct ListenToYouTubeResult {
    public let streamURL: URL
    public let title: String
}

public enum ListenToYouTubeStatus {
    case waitingForConversion
    case downloading(Int)
    case converting(Int)
    case success(ListenToYouTubeResult)
}

open class ListenToYouTubeClient {
    open static let sharedClient = ListenToYouTubeClient()
    
    open func audioStreamProducer(_ url: URL) -> SignalProducer<ListenToYouTubeStatus, NSError> {
        return statusURLProducer(url).flatMap(.latest, transform: { self.conversionStatusProducer($0) })
    }
    
    internal func statusURLProducer(_ videoURL: URL) -> SignalProducer<URL, NSError> {
        return SignalProducer<URL, NSError> { observer, disposable in
            let parameters = ["mediaurl": videoURL.absoluteString,
                              "client_urlmap": "none"]
            Alamofire.request(baseURL.appendingPathComponent("cc/conversioncloud.php"), withMethod: .post, parameters: parameters, encoding: .url, headers: nil).responseString { (response) in
                switch(response.result) {
                case .success(let jsonp):
                    guard let context = JSContext(), let evaluatedJSONP = context.evaluateScript(jsonp) else {
                        observer.sendFailed(NSError(domain: "JSContextError", code: 0, userInfo: nil))
                        return
                    }

                    if evaluatedJSONP.isUndefined {
                        observer.sendFailed(NSError(domain: "JSONP error", code: 0, userInfo: nil))
                        return
                    }
                    
                    let statusURLString = evaluatedJSONP.toDictionary()["statusurl"] as! String
                    
                    if let statusURL = URL(string: statusURLString) {
                        observer.sendNext(statusURL)
                        observer.sendCompleted()
                    }
                case .failure(let error):
                    observer.sendFailed(error)
                }
            }
        }
    }
    
    internal func conversionStatusProducer(_ statusURL: URL) -> SignalProducer<ListenToYouTubeStatus, NSError> {
        return SignalProducer<ListenToYouTubeStatus, NSError> { observer, disposable in
            Alamofire.request(statusURL.absoluteString+"&json", withMethod: .get).responseString { (response) in
                switch(response.result) {
                case .success(let jsonp):
                    guard let context = JSContext(), let evaluatedJSONP = context.evaluateScript(jsonp) else {
                         observer.sendFailed(NSError(domain: "JSContextError", code: 0, userInfo: nil))
                        return
                    }
                    
                    if evaluatedJSONP.isUndefined {
                       observer.sendFailed(NSError(domain: "JSONP error", code: 0, userInfo: nil))
                        return
                    }
                    
                    let json = evaluatedJSONP.toDictionary()

                    if let status = json?["status"] as? [String: AnyObject], let attributes = status["@attributes"] as? [String: AnyObject] {
                        switch(attributes["step"] as! String) {
                        case "ticket":
                            observer.sendNext(.waitingForConversion)
                            
                        case "convert":
                            if let percent = Int(attributes["percent"] as! String) {
                                observer.sendNext(ListenToYouTubeStatus.converting(percent))
                            }
                            
                        case "download":
                            if let percent = Int(attributes["percent"] as! String) {
                                observer.sendNext(ListenToYouTubeStatus.downloading(percent))
                            }
                            
                        case "finished":
                            let fileName = json?["file"] as! String
                            let videoName = fileName.substring(to: fileName.characters.index(fileName.startIndex, offsetBy: fileName.characters.count-4))
                            
                            if let streamURL = URL(string: json?["downloadurl"] as! String) {
                                let result = ListenToYouTubeResult(streamURL: streamURL, title: videoName)
                                observer.sendNext(ListenToYouTubeStatus.success(result))
                                observer.sendCompleted()
                            } else {
                                observer.sendFailed(NSError(domain: "StreamURLError", code: 0, userInfo: nil))
                            }
                            return
                            
                        default:
                            print("UNHANDLED STATUS: \(attributes["step"])")
                        }
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + Double(Int64(3*NSEC_PER_SEC)) / Double(NSEC_PER_SEC), execute: {
                        disposable += self.conversionStatusProducer(statusURL).start(observer)
                    })
                    
                case .failure(let error):
                    observer.sendFailed(error)
                }
            }
        }
    }
}
