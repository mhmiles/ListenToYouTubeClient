//
//  ListenToYouTubeClient.swift
//  ListenToYouTubeClient
//
//  Created by Miles Hollingsworth on 6/28/16.
//  Copyright © 2016 Miles Hollingsworth. All rights reserved.
//

import Foundation
import ReactiveCocoa
import Alamofire
import JavaScriptCore

private let baseURL = NSURL(string: "http://www.listentoyoutube.com")!

public struct ListenToYouTubeResult {
    public let streamURL: NSURL
    public let title: String
}

public enum ListenToYouTubeStatus {
    case WaitingForConversion
    case Downloading(Int)
    case Converting(Int)
    case Success(ListenToYouTubeResult)
}

public class ListenToYouTubeClient {
    public static let sharedClient = ListenToYouTubeClient()
    
    public func audioStreamProducer(url: NSURL) -> SignalProducer<ListenToYouTubeStatus, NSError> {
        return statusURLProducer(url).flatMap(.Latest, transform: { [unowned self] statusURL -> SignalProducer<ListenToYouTubeStatus, NSError>  in
            return self.conversionStatusProducer(statusURL)
        })
    }
    
    internal func statusURLProducer(videoURL: NSURL) -> SignalProducer<NSURL, NSError> {
        return SignalProducer<NSURL, NSError> { observer, disposable in
            let parameters = ["mediaurl": videoURL.absoluteString,
                              "client_urlmap": "none"]
            
            Alamofire.request(.POST, baseURL.URLByAppendingPathComponent("cc/conversioncloud.php"), parameters: parameters, encoding: .URL, headers: nil).responseString { (response) in
                switch(response.result) {
                case .Success(let jsonp):
                    let context = JSContext()
                    let evaluatedJSONP = context.evaluateScript(jsonp)
                    if evaluatedJSONP.isUndefined {
                        observer.sendFailed(NSError(domain: "JSONP error", code: 0, userInfo: nil))
                        return
                    }
                    
                    let statusURLString = evaluatedJSONP.toDictionary()["statusurl"] as! String
                    
                    if let statusURL = NSURL(string: statusURLString) {
                        observer.sendNext(statusURL)
                        observer.sendCompleted()
                    }
                case .Failure(let error):
                    observer.sendFailed(error)
                }
            }
        }
    }
    
    internal func conversionStatusProducer(statusURL: NSURL) -> SignalProducer<ListenToYouTubeStatus, NSError> {
        return SignalProducer<ListenToYouTubeStatus, NSError> { observer, disposable in
            Alamofire.request(.GET, statusURL.absoluteString+"&json").responseString { (response) in
                switch(response.result) {
                case .Success(let jsonp):
                    let context = JSContext()
                    let evaluatedJSONP = context.evaluateScript(jsonp)
                    if evaluatedJSONP.isUndefined {
                       observer.sendFailed(NSError(domain: "JSONP error", code: 0, userInfo: nil))
                        return
                    }
                    
                    let json = evaluatedJSONP.toDictionary()

                    if let status = json["status"] as? [String: AnyObject], attributes = status["@attributes"] as? [String: AnyObject] {
                        switch(attributes["step"] as! String) {
                        case "ticket":
                            observer.sendNext(.WaitingForConversion)
                            
                        case "convert":
                            if let percent = Int(attributes["percent"] as! String) {
                                observer.sendNext(ListenToYouTubeStatus.Converting(percent))
                            }
                            
                        case "download":
                            if let percent = Int(attributes["percent"] as! String) {
                                observer.sendNext(ListenToYouTubeStatus.Downloading(percent))
                            }
                            
                        case "finished":
                            let fileName = json["file"] as! String
                            let videoName = fileName.substringToIndex(fileName.startIndex.advancedBy(fileName.characters.count-4))
                            
                            if let streamURL = NSURL(string: json["downloadurl"] as! String) {
                                let result = ListenToYouTubeResult(streamURL: streamURL, title: videoName)
                                observer.sendNext(ListenToYouTubeStatus.Success(result))
                                observer.sendCompleted()
                            }
                            return
                            
                        default:
                            print("UNHANDLED STATUS: \(attributes["step"])")
                        }
                    }
                    
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, Int64(3*NSEC_PER_SEC)), dispatch_get_main_queue(), {
                        disposable += self.conversionStatusProducer(statusURL).start(observer)
                    })
                    
                case .Failure(let error):
                    observer.sendFailed(error)
                }
            }
        }
    }
}