import Foundation

class URLSessionDataStreamDelegate: NSObject, URLSessionDataDelegate {
    var headersInner: [String : AnyObject] = [:]
    
    var received: (_ data: Data) -> ()
    var validate: (_ response: URLResponse) -> URLSession.ResponseDisposition
    
    public init(
        received: @escaping (_ data: Data) -> (),
        validate: @escaping (_ response: URLResponse) -> URLSession.ResponseDisposition = { _ in return .allow }
    ) {
        self.received = received
        self.validate = validate
    }
    
    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard let serverTrust = challenge.protectionSpace.serverTrust else {
            return (.cancelAuthenticationChallenge, nil)
        }
        
        return (.useCredential, URLCredential(trust: serverTrust))
    }
    
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse) async -> URLSession.ResponseDisposition {
        
        if((response as! HTTPURLResponse).statusCode != 200){
            return .cancel
        }

        headersInner = [:]
        for (key, value) in (response as! HTTPURLResponse).allHeaderFields {
            headersInner[key as! String] = value as AnyObject //as? String
        }

        let res = self.validate(response)

        return res //.allow
    }

    
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // Callback once all of the data has been received when using Content-Length
        self.received(data)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        assert(task is URLSessionDataTask)
        
    }
}
