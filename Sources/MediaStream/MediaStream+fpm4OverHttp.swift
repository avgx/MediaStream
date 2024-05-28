import Foundation
import CoreImage
import Transcoding
import Logging

extension MediaStream {
    @MediaStreamActor
    public func fpm4OverHttp(request: URLRequest) async -> AsyncStream<Message> {
        let sid = self.sid
        let logger = self.logger
        return AsyncStream(bufferingPolicy: .bufferingNewest(25)) { continuation in
            let start = Date()
            
            newMessageSink = continuation
            
            let stats = Stats()
            
            let decoder = VideoDecoder(config: .init(outputBufferCount: 30))
            let fmp4 = VideoDecoderFmp4Adaptor(videoDecoder: decoder, uuid: sid, logger: nil)
            
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
                logger?.log(level: .info, "\(sid) connect done \(-start.timeIntervalSinceNow)")
                continuation.yield(Message.connected)
                return .allow
            })
            
            let decodeTask = Task { [stats] in
                for await decodedSampleBuffer in decoder.decodedSampleBuffers {
                    logger?.log(level: .info, "decoded frame \(stats.decodedNumber) \(sid) at \(-start.timeIntervalSinceNow)")
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
                        
                        let decodedFrame: DecodedFrame = .init(streamId: sid, ts: nil, frame: ci, bytesLoaded: stats.bytesLoaded, timeSinceStart: -start.timeIntervalSinceNow, decodedNumber: stats.decodedNumber)
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
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            self.session = session
            let socket = session.dataTask(with: request)
            socket.resume()
            
            continuation.onTermination = { _ in
                logger?.log(level: .info, "continuation onTermination  \(sid)")
                //                t.cancel()
                socket.cancel()
                session.finishTasksAndInvalidate()
                decodeTask.cancel()
                decoder.invalidate()
            }
        }
    }
}
