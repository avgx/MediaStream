import XCTest
import Logging
@testable import MediaStream

final class MediaStreamTests: XCTestCase {
    let logger: Logger = {
        var x = Logger(label: "MediaStream")
        x.logLevel = .debug
        return x
        //Logger(subsystem: "MediaStream", category: "MediaStreamTests")
    }()
    
    func test_fpm4OverHttp() async throws {
        let uuid = UUID()
        let vs = MediaStream(sid: uuid, logger: logger)
        var request = URLRequest(url: URL(string: "http://try.axxonsoft.com:8000/asip-api/live/media/DEMOSERVER/DeviceIpint.6/SourceEndpoint.video:0:1?format=mp4&key_frames=0&id=\(uuid.uuidString)")!)
        request.setValue("Basic cm9vdDpyb290", forHTTPHeaderField: "Authorization")
        
        let stream = await vs.fpm4OverHttp(request: request)
        var n = 0
        
        for await message in stream {
            n += 1
            if n > 100 { break }
            switch message {
            case .connecting:
                print("connecting")
            case .connected:
                print("connected")
            case .frame(let f):
                print("frame \(f.decodedNumber) \(f.kBps)kB/s")
            case .error(_):
                print("error")
            case .disconnected:
                print("disconnected")
            case .ended:
                print("stopped")
            }
        }
        print("done")
    }
    
    func test_fpm4OverWs() async throws {
        let uuid = UUID()
        let vs = MediaStream(sid: uuid, logger: logger)
        var request = URLRequest(url: URL(string: "http://try.axxonsoft.com:8000/asip-api/ws")!)
        request.setValue("Basic cm9vdDpyb290", forHTTPHeaderField: "Authorization")
        
        let cmd = Ws.cmdPlayLive(streamId: uuid, endpoint: "DEMOSERVER/DeviceIpint.6/SourceEndpoint.video:0:1", format: .mp4, speed: 1, keyFrames: false)
        
        let stream = await vs.fpm4OverWs(request: request, cmd: cmd)
        var n = 0
        
        for await message in stream {
            n += 1
            if n > 100 { break }
            switch message {
            case .connecting:
                print("connecting")
            case .connected:
                print("connected")
            case .frame(let f):
                print("frame \(f.decodedNumber) \(f.streamId) \(f.bytesLoaded) \(f.fps)f/s \(f.kBps)kB/s \(f.ts?.timeIntervalSince1970)")
            case .error(_):
                print("error")
                break
            case .disconnected:
                print("disconnected")
                break
            case .ended:
                print("stopped")
            }
        }
        print("done")
    }
    
    func test_fpm4OverWsArchive() async throws {
        let uuid = UUID()
        let vs = MediaStream(sid: uuid, logger: logger)
        
        var request = URLRequest(url: URL(string: "http://try.axxonsoft.com:8000/asip-api/ws")!)
        request.setValue("Basic cm9vdDpyb290", forHTTPHeaderField: "Authorization")
        
        let cmd = Ws.cmdPlayArchive(streamId: uuid, endpoint: "DEMOSERVER/DeviceIpint.6/SourceEndpoint.video:0:0", beginTime: "20240418T090649.651", archive: "DEMOSERVER/MultimediaStorage.AliceBlue/MultimediaStorage", format: .mp4, speed: 1, keyFrames: false)
        
        let stream = await vs.fpm4OverWs(request: request, cmd: cmd)
        var n = 0
        
        for await message in stream {
            n += 1
            if n > 100 { break }
            switch message {
            case .connecting:
                print("connecting")
            case .connected:
                print("connected")
            case .frame(let f):
                print("frame \(f.decodedNumber) \(f.streamId) \(f.bytesLoaded) \(f.fps)f/s \(f.kBps)kB/s \(f.ts?.timeIntervalSince1970)")
            case .error(_):
                print("error")
                break
            case .disconnected:
                print("disconnected")
                break
            case .ended:
                print("stopped")
            }
        }
        print("done")
    }
    
    func test_fpm4OverHttp_stop() async throws {
        let uuid = UUID()
        let vs = MediaStream(sid: uuid, logger: logger)
        var request = URLRequest(url: URL(string: "http://try.axxonsoft.com:8000/asip-api/live/media/DEMOSERVER/DeviceIpint.6/SourceEndpoint.video:0:0?format=mp4&key_frames=0&id=\(uuid.uuidString)")!)
        request.setValue("Basic cm9vdDpyb290", forHTTPHeaderField: "Authorization")
        
        Task { [vs] in
            try await Task.sleep(nanoseconds:NSEC_PER_SEC * 5)
            print("send finish")
            vs.finish()
        }
        
        let stream = await vs.fpm4OverHttp(request: request)
        var n = 0
        
        for await message in stream {
            n += 1
            //                if n > 100 { break }
            switch message {
            case .connecting:
                print("connecting")
            case .connected:
                print("connected")
            case .frame(let f):
                print("frame \(f.decodedNumber) \(f.streamId) \(f.bytesLoaded) \(f.fps)f/s \(f.kBps)kB/s \(f.ts?.timeIntervalSince1970)")
            case .error(_):
                print("error")
                break
            case .disconnected:
                print("disconnected")
                break
            case .ended:
                print("stopped")
            }
        }
        
        
        print("done")
    }
    
    func test_fpm4OverWs_stop() async throws {
        let uuid = UUID()
        let vs = MediaStream(sid: uuid, logger: logger)
        var request = URLRequest(url: URL(string: "http://try.axxonsoft.com:8000/asip-api/ws")!)
        request.setValue("Basic cm9vdDpyb290", forHTTPHeaderField: "Authorization")
        
        Task { [vs] in
            try await Task.sleep(nanoseconds:NSEC_PER_SEC * 15)
            print("send ugly-token")
            await vs.fpm4OverWs(updateToken: Ws.cmdUpdate(token: "ugly-token"))
            
            try await Task.sleep(nanoseconds:NSEC_PER_SEC * 5)
            print("send finish")
            vs.finish()
        }
        
        
        let cmd = Ws.cmdPlayLive(streamId: uuid, endpoint: "DEMOSERVER/DeviceIpint.6/SourceEndpoint.video:0:1", format: .mp4, speed: 1, keyFrames: false)
        
        let stream = await vs.fpm4OverWs(request: request, cmd: cmd)
        var n = 0
        
        for await message in stream {
            n += 1
            //                if n > 100 { break }
            switch message {
            case .connecting:
                print("connecting")
            case .connected:
                print("connected")
            case .frame(let f):
                print("frame \(f.decodedNumber) \(f.streamId) \(f.bytesLoaded) \(f.fps)f/s \(f.kBps)kB/s \(f.ts?.timeIntervalSince1970)")
            case .error(_):
                print("error")
                break
            case .disconnected:
                print("disconnected")
                break
            case .ended:
                print("stopped")
            }
        }
        
        
        print("done")
    }
}
