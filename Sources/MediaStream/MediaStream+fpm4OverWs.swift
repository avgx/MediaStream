import Foundation
import CoreImage
import Transcoding
import Get
import Logging

extension MediaStream {
    @MediaStreamActor
    public func fpm4OverWs(updateToken: Ws.UpdateToken) async {
        try? await ws?.send(updateToken)
    }
    
    @MediaStreamActor
    public func fpm4OverWs(request: URLRequest, cmd: Ws.Command) async -> AsyncStream<Message> {
        let sid = self.sid
        let logger = self.logger
        return AsyncStream(bufferingPolicy: .bufferingNewest(25)) { continuation in
            let start = Date()
            
            newMessageSink = continuation
            
            let stats = Stats()
            
            let decoder = VideoDecoder(config: .init(outputBufferCount: 30))
            let fmp4 = VideoDecoderFmp4Adaptor(videoDecoder: decoder, uuid: sid, logger: logger)
            
            let ws: WebSocket2 = .init(request: request)
            
            let feed = Task { [start, stats, ws] in //@WsActor in
                do {
                    try await ws.connect()
                    logger?.log(level: .info, "\(sid) ws connect done \(-start.timeIntervalSinceNow)")
                    continuation.yield(Message.connected)
                    try await ws.send(cmd)
                    
                    for try await message in ws.messages {
                        let frame = try Ws.parse(data: message)
                        stats.bytesLoaded += message.count
                        stats.bytesPerSecond = Double(stats.bytesLoaded) / Double(-start.timeIntervalSinceNow)
                        stats.ts = frame.ts
                        if frame.isStopped {
                            continuation.yield(Message.ended)
                            break
                        }
                        if Task.isCancelled {
                            break
                        }
                        try fmp4.enqueue(data: frame.payload, ts: frame.ts)
                    }
                    logger?.log(level: .info, "\(sid) ws read done")
                    try ws.disconnect()
                    continuation.yield(Message.disconnected)
                    continuation.finish()
                } catch {
                    logger?.log(level: .info, "\(sid) ws messages error \(error.localizedDescription)!")
                    continuation.finish()
                }
            }
            
            let decodeTask = Task { [start, stats] in
                for await (decodedSampleBuffer, ts) in decoder.decodedSampleBuffers {
                    logger?.log(level: .info, "\(sid) decoded frame \(stats.decodedNumber) \(sid) at \(-start.timeIntervalSinceNow) | \(stats.ts?.timeIntervalSince1970) \(ts?.timeIntervalSince1970)")
                    if Task.isCancelled {
                        break
                    }
                    
                    stats.decodedNumber += 1
                    
                    if decoder.isBufferFull {
                        logger?.log(level: .info, "skip decoded frame for \(sid) due to isBufferFull")
                        continue
                    }
                    
                    if let imageBuffer = decodedSampleBuffer.imageBuffer {
                        let ci = CIImage(cvImageBuffer: imageBuffer)
                        
                        let decodedFrame: DecodedFrame = .init(streamId: sid, ts: ts, frame: ci, bytesLoaded: stats.bytesLoaded, timeSinceStart: -start.timeIntervalSinceNow, decodedNumber: stats.decodedNumber)
                        let res = continuation.yield(Message.frame(decodedFrame))
                        switch res {
                        case .enqueued(let remaining):
                            logger?.log(level: .info, "\(sid) remaining:\(remaining)")
                        default:
                            { }()
                        }
                    }
                }
                
                logger?.log(level: .info, "decode task end \(sid)")
            }
            
            continuation.yield(Message.connecting)
            self.ws = ws
            
            continuation.onTermination = { [weak self] _ in
                logger?.log(level: .info, "continuation onTermination \(sid)")
                //                t.cancel()
//                socket.cancel()
//                session.finishTasksAndInvalidate()
                self?.ws = nil
                feed.cancel()
                decodeTask.cancel()
                decoder.invalidate()
            }
        }
    }
    
    @MediaStreamActor
    public func fpm4OverWsRaw(request: URLRequest, cmd: Ws.Command) async -> AsyncStream<Message> {
        let sid = self.sid
        let logger = self.logger
        return AsyncStream(bufferingPolicy: .bufferingNewest(25)) { continuation in
            let start = Date()
            
            newMessageSink = continuation
            
            let ws: WebSocket2 = .init(request: request)
            
            let feed = Task { [start, ws] in //@WsActor in
                do {
                    try await ws.connect()
                    logger?.log(level: .info, "\(sid) ws connect done \(-start.timeIntervalSinceNow)")
                    continuation.yield(Message.connected)
                    try await ws.send(cmd)
                    
                    for try await message in ws.messages {
                        let frame = try Ws.parse(data: message)
                        if frame.isStopped {
                            continuation.yield(Message.ended)
                            break
                        }
                        if Task.isCancelled {
                            break
                        }
                        continuation.yield(Message.raw(frame, message.count, start))
                    }
                    logger?.log(level: .info, "\(sid) ws read done")
                    try ws.disconnect()
                    continuation.yield(Message.disconnected)
                    continuation.finish()
                } catch {
                    logger?.log(level: .info, "\(sid) ws messages error \(error.localizedDescription)!")
                    continuation.finish()
                }
            }
            
            continuation.yield(Message.connecting)
            self.ws = ws
            
            continuation.onTermination = { [weak self] _ in
                logger?.log(level: .info, "continuation onTermination \(sid)")
                self?.ws = nil
                feed.cancel()
            }
        }
    }
}
