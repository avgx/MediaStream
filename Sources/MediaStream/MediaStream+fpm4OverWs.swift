import Foundation
import CoreImage
import Transcoding
import Get
import OSLog

extension MediaStream {
    @MediaStreamActor
    public func fpm4OverWs(updateToken: Ws.UpdateToken) async {
        try? await ws?.send(updateToken)
    }
    
    @MediaStreamActor
    public func fpm4OverWs(sid: UUID, request: URLRequest, cmd: Ws.Command, logger: Logger?) async -> AsyncStream<Message> {
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
                    logger?.log("\(sid) ws connect done \(-start.timeIntervalSinceNow)")
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
                        try fmp4.enqueue(data: frame.payload)
                    }
                    logger?.log("\(sid) ws read done")
                    try ws.disconnect()
                    continuation.yield(Message.disconnected)
                    continuation.finish()
                } catch {
                    logger?.log("\(sid) ws messages error \(error.localizedDescription)!")
                    continuation.finish()
                }
            }
            
            let decodeTask = Task { [start, stats] in
                for await decodedSampleBuffer in decoder.decodedSampleBuffers {
                    logger?.log("\(sid) decoded frame \(stats.decodedNumber) \(sid) at \(-start.timeIntervalSinceNow)")
                    if Task.isCancelled {
                        break
                    }
                    
                    stats.decodedNumber += 1
                    
                    if decoder.isBufferFull {
                        logger?.log("skip decoded frame for \(sid) due to isBufferFull")
                        continue
                    }
                    
                    if let imageBuffer = decodedSampleBuffer.imageBuffer {
                        let ci = CIImage(cvImageBuffer: imageBuffer)
                        
                        let decodedFrame: DecodedFrame = .init(streamId: sid, ts: stats.ts, frame: ci, bytesLoaded: stats.bytesLoaded, timeSinceStart: -start.timeIntervalSinceNow, decodedNumber: stats.decodedNumber)
                        let res = continuation.yield(Message.frame(decodedFrame))
                        switch res {
                        case .enqueued(let remaining):
                            logger?.log("\(sid) remaining:\(remaining)")
                        default:
                            { }()
                        }
                    }
                }
                
                logger?.log("decode task end \(sid)")
            }
            
            continuation.yield(Message.connecting)
            self.ws = ws
            
            continuation.onTermination = { [weak self] _ in
                logger?.log("continuation onTermination \(sid)")
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
}
