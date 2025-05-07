import Foundation
import Get
import CoreImage
import Logging

public class MediaStream {
//TODO:    func mjpeg_over_http(URLRequest)
//TODO:    func mjpeg_over_ws(URLRequest, Parser)
//TODO:    func mjpeg_snapshots_over_ws(URLRequest)
    
    public enum Message {
        case connecting
        case connected
        case frame(DecodedFrame)
        case raw(Frame, Int, Date)    //frame, bytesLoaded, start (Date)
        case ended
        case error(Error)
        case disconnected
    }
    
    public class Stats {
        public var bytesLoaded = 0
        public var decodedNumber = 0
        public var ts: Date? = nil
        public var bytesPerSecond = 0.0
    }
    
    public struct Frame {
        public let streamId: UUID
        public let ts: Date
        public let isSubtitles: Bool
        public let payload: Data
        
        public var isStopped: Bool {
            return ts > .distantFuture
        }
    }
    
    public struct DecodedFrame {
        public let streamId: UUID
        public let ts: Date?
        public let frame: CIImage
        public let bytesLoaded: Int
        public let timeSinceStart: TimeInterval
        public let decodedNumber: Int
        
        public var isStopped: Bool {
            return (ts ?? Date()) > .distantFuture
        }
        
        public var bytesPerSecond: Double {
            return Double(bytesLoaded) / timeSinceStart
        }
        
        public var kBps: Double {
            return bytesPerSecond / 1024.0
        }
        
        public var fps: Double {
            return Double(decodedNumber) / timeSinceStart
        }
    }
    
    var newMessageSink: AsyncStream<Message>.Continuation?
    weak var ws: WebSocket2?
    weak var session: URLSession?
    
    let logger: Logger?
    public let sid: UUID
    
    public func finish() {
        newMessageSink?.finish()
        newMessageSink = nil
        session?.finishTasksAndInvalidate()
        session = nil
    }
    
    public init(sid: UUID, logger: Logger?) {
        self.sid = sid
        self.logger = logger
        self.newMessageSink = nil
        self.ws = nil
        self.session = nil
        logger?.log(level: .info, "\(String(describing: self)) \(self.sid)")
    }
    
    deinit {
        logger?.log(level: .info, "~\(String(describing: self)) \(self.sid)")
    }
}

