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
    public static let shared = ListenToYouTubeClient()
    
    public func audioStreamProducer(_ url: URL) -> SignalProducer<ListenToYouTubeStatus, NSError> {
        return statusURLProducer(url).flatMap(.latest, transform: { self.conversionStatusProducer($0) })
    }
    
    internal func statusURLProducer(_ videoURL: URL) -> SignalProducer<URL, NSError> {
        return SignalProducer<URL, NSError> { observer, disposable in
            let parameters = ["mediaurl": videoURL.absoluteString,
                              "client_urlmap": "none"]
            Alamofire.request(baseURL.appendingPathComponent("cc/conversioncloud.php"), method: .post, parameters: parameters).responseString { (response) in
                switch(response.result) {
                case .success(let jsonp):
                    guard let context = JSContext(), let evaluatedJSONP = context.evaluateScript(jsonp) else {
                        observer.send(error: NSError(domain: "JSContextError", code: 0, userInfo: nil))
                        return
                    }

                    if evaluatedJSONP.isUndefined {
                        observer.send(error: NSError(domain: "JSONP error", code: 0, userInfo: nil))
                        return
                    }
                    
                    guard let statusURLString = evaluatedJSONP.toDictionary()["statusurl"] as? String else {
                        observer.send(error: NSError(domain: "StatusURLError", code: 0, userInfo: nil))
                        return
                    }
                    
                    if let statusURL = URL(string: statusURLString) {
                        observer.send(value: statusURL)
                        observer.sendCompleted()
                    }
                    
                case .failure(let error):
                    observer.send(error: error as NSError)
                }
            }
        }
    }
    
    internal func conversionStatusProducer(_ statusURL: URL) -> SignalProducer<ListenToYouTubeStatus, NSError> {
        return SignalProducer<ListenToYouTubeStatus, NSError> { observer, disposable in
            Alamofire.request(statusURL.absoluteString+"&json", method: .get).responseString { (response) in
                switch(response.result) {
                case .success(let jsonp):
                    guard let context = JSContext(), let evaluatedJSONP = context.evaluateScript(jsonp) else {
                         observer.send(error: NSError(domain: "JSContextError", code: 0, userInfo: nil))
                        return
                    }
                    
                    if evaluatedJSONP.isUndefined {
                       observer.send(error: NSError(domain: "JSONP error", code: 0, userInfo: nil))
                        return
                    }
                    
                    let json = evaluatedJSONP.toDictionary()

                    if let status = json?["status"] as? [String: AnyObject], let attributes = status["@attributes"] as? [String: AnyObject] {
                        switch(attributes["step"] as! String) {
                        case "ticket":
                            observer.send(value: .waitingForConversion)
                            
                        case "convert":
                            if let percent = Int(attributes["percent"] as! String) {
                                observer.send(value: ListenToYouTubeStatus.converting(percent))
                            }
                            
                        case "download":
                            if let percent = Int(attributes["percent"] as! String) {
                                observer.send(value: ListenToYouTubeStatus.downloading(percent))
                            }
                            
                        case "finished":
                            let fileName = json?["file"] as! String
                            let videoName = fileName.substring(to: fileName.characters.index(fileName.startIndex, offsetBy: fileName.characters.count-4))
                            
                            if let streamURL = URL(string: json?["downloadurl"] as! String) {
                                let result = ListenToYouTubeResult(streamURL: streamURL, title: videoName)
                                observer.send(value: ListenToYouTubeStatus.success(result))
                                observer.sendCompleted()
                            } else {
                                observer.send(error: NSError(domain: "StreamURLError", code: 0, userInfo: nil))
                            }
                            
                            return
                            
                        default:
                            print("UNHANDLED STATUS: \(String(describing: attributes["step"]))")
                        }
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + Double(Int64(3*NSEC_PER_SEC)) / Double(NSEC_PER_SEC), execute: {
                        disposable += self.conversionStatusProducer(statusURL).start(observer)
                    })
                    
                case .failure(let error):
                    observer.send(error: error as NSError)
                }
            }
        }
    }
}
