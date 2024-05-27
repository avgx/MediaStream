import Foundation
import CoreImage
import Transcoding
import OSLog

extension MediaStream {
    @MediaStreamActor
    public func fpm4OverHttp(sid: UUID, request: URLRequest, logger: Logger?) async -> AsyncStream<Message> {
        return AsyncStream(bufferingPolicy: .bufferingNewest(25)) { continuation in
            let start = Date()
            
            newMessageSink = continuation
            
            let stats = Stats()
            
            let decoder = VideoDecoder(config: .init(outputBufferCount: 30))
            let fmp4 = VideoDecoderFmp4Adaptor(videoDecoder: decoder, uuid: sid, logger: logger)
            
            let delegate = URLSessionDataStreamDelegate(received: { [stats] data in
                do {
                    //print("URLSessionDataStream \(uuid) \(data.count)")
                    stats.bytesLoaded += data.count
                    stats.bytesPerSecond = Double(stats.bytesLoaded) / Double(-start.timeIntervalSinceNow)
                    try fmp4.enqueue(data: data)
                } catch {
                    print(error)
                    continuation.finish()
                }
            }, validate: { _ in
                logger?.log("\(sid) connect done \(-start.timeIntervalSinceNow)")
                continuation.yield(Message.connected)
                return .allow
            })
            
            let decodeTask = Task { [stats] in
                for await decodedSampleBuffer in decoder.decodedSampleBuffers {
                    logger?.log("decoded frame \(stats.decodedNumber) \(sid) at \(-start.timeIntervalSinceNow)")
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
                        
                        let decodedFrame: DecodedFrame = .init(streamId: sid, ts: nil, frame: ci, bytesLoaded: stats.bytesLoaded, timeSinceStart: -start.timeIntervalSinceNow, decodedNumber: stats.decodedNumber)
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
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            
            let socket = session.dataTask(with: request)
            socket.resume()
            
            continuation.onTermination = { _ in
                logger?.log("continuation onTermination  \(sid)")
                //                t.cancel()
                socket.cancel()
                session.finishTasksAndInvalidate()
                decodeTask.cancel()
                decoder.invalidate()
            }
        }
    }
}