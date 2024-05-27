import Foundation

public enum Ws {}

extension Ws {
    public struct Command: Codable, Sendable {
        public enum Method: String, Codable, Sendable {
            case play
            case stop
        }
        public enum Format: String, Codable, Sendable {
            case mp4
            case jpeg
        }
        public let method: Method
        public let streamId: UUID
        
        public let endpoint: String?
        public let format: Format?
        
        /// webclient/browse/src/types/ws.ts
        public let keyFrames: Bool?
        public let speed: Int?
        public let archive: String?
        public let forward: Bool?
        public let width: Int?
        public let height: Int?
        public let vc: Int?             // VideoCompression = 0 | 1 | 2 | 3 | 4 | 5 | 6;
        public let beginTime: String?
    }
    
    public struct UpdateToken: Encodable, Sendable {
        public let method: String = "update_token"
        public let auth_token: String
    }
    
    ///  {"include":["hosts/AVGXNUC/DeviceIpint.64/SourceEndpoint.video:0:0"]}
    ///  {"exclude":["hosts/AVGXNUC/DeviceIpint.64/SourceEndpoint.video:0:0"]}
    public struct EventSubscription: Codable, Sendable {
        public let include: [String]
        public let exclude: [String]?
    }
}

extension Ws.Command {
    public func with(updatedTime: String) -> Self {
        guard self.beginTime != nil else {
            return self
        }
        
        return Self(method: self.method, streamId: self.streamId, endpoint: self.endpoint, format: self.format, keyFrames: self.keyFrames, speed: self.speed, archive: self.archive, forward: nil, width: self.width, height: self.height, vc: self.vc, beginTime: updatedTime)
    }
}
extension Ws {
    public static func cmdUpdate(token: String) -> UpdateToken {
        return .init(auth_token: token)
    }
    
    public static func cmdPlayLive(
        streamId: UUID,
        endpoint: String,
        format: Command.Format = .mp4,
        speed: Int = 1,
        keyFrames: Bool = false
    ) -> Command {
        Command(method: .play, streamId: streamId, endpoint: endpoint, format: format, keyFrames: keyFrames, speed: speed, archive: nil, forward: nil, width: nil, height: nil, vc: nil, beginTime: nil)
    }
    
    public static func cmdPlayArchive(
        streamId: UUID,
        endpoint: String,
        beginTime: String,
        archive: String,
        format: Command.Format = .mp4,
        speed: Int = 1,
        keyFrames: Bool = false
    ) -> Command {
        Command(method: .play, streamId: streamId, endpoint: endpoint, format: format, keyFrames: keyFrames, speed: speed, archive: archive, forward: nil, width: nil, height: nil, vc: nil, beginTime: beginTime)
    }
    
    public static func cmdFrameArchive(
        streamId: UUID,
        endpoint: String,
        beginTime: String,
        archive: String,
        keyFrames: Bool = false
    ) -> Command {
        Command(method: .play, streamId: streamId, endpoint: endpoint, format: .jpeg, keyFrames: keyFrames, speed: 0, archive: archive, forward: nil, width: nil, height: 720, vc: 3, beginTime: beginTime)
    }
    
    public static func cmdStop(
        streamId: UUID
    ) -> Command {
        Command(method: .stop, streamId: streamId, endpoint: nil, format: nil, keyFrames: nil, speed: nil, archive: nil, forward: nil, width: nil, height: nil, vc: nil, beginTime: nil)
    }
    
//    public struct Frame {
//        let streamId: UUID
//        let ts: Date
//        let isSubtitles: Bool
//        let payload: Data
//    }
//    
//    public struct DecodedFrame {
//        let streamId: UUID
//        let ts: Date?
//        let frame: CIImage
//        let frameNumber: Int
//        let bytesLoaded: Int
//        let decodedNumber: Int
//        
//        public var isStopped: Bool {
//            return (ts ?? Date()) > .distantFuture
//        }
//    }
    
    public static func parse(data: Data) throws -> MediaStream.Frame {
        
        // in AO 1.0 there is one leading zero bytes
        // in AO 2.0 there are two leading zero bytes
        // idLen(2)|idBytes(var)|tsBytes(8)|dataBytes(var)
        // 2018-03-08
        // idLen(2)|idBytes(var)|tsBytes(8)|prerollByte(1)|dataBytes(var)
        // 2022-08-18
        // signLen(1)|idLen(2)|idBytes(var)|tsBytes(8)|prerollByte(1)|dataBytes(var)
        
        //precondition(data.count >= 2 + 36 + 8)   // type(1) + idLen(1) + id(36) + ts(8) + jpegData
        let d0: UInt8 = data.object(at: 0)
        let d1: UInt8 = data.object(at: 1)
        let d2: UInt8 = data.object(at: 2)
        
        let idOffset: Int = d1 == 0 ? 3 : 2
        let idLen: Int = Int(d1 == 0 ? d2 : d1)
        let uuidLen = UUID().uuidString.lowercased().count
        //precondition(idLen == uuidLen)  //we always send uuid as streamId
        let idBytes: [UInt8] = data.dropFirst(idOffset).prefix(Int(idLen)).copyBytes(as: UInt8.self)
        guard let streamIds = String(bytes: idBytes, encoding: .utf8), let streamId = UUID(uuidString: streamIds) else {
            throw URLError(.cannotDecodeContentData)
        }
        
        // признак (текстовые данные(1) или бинарные(0))
        let isSubtitles: Bool = d0 == 1 && d1 == 0
        
        let tsOffset = idOffset + idLen
        let tsLen = 8
        let tsBytes: [UInt8] = data.dropFirst(tsOffset).prefix(tsLen).copyBytes(as: UInt8.self)
        
        
        let timeUint64 = UInt64(tsBytes)
        let unixTimestamp = Int(timeUint64) - 2208988800000
        let ts = Date(timeIntervalSince1970: TimeInterval(Double(unixTimestamp) / 1_000))
        
        //00 00 03 90 17 45 45 f7
        //00 00 02 00 00 00 00 00   19690907T184735.552000
        //00 00 04 FF 00 00 00 00   20740127T132611.584000
        precondition(tsBytes[0] == 0x00)
        precondition(tsBytes[1] == 0x00)
        //precondition(tsBytes[2] >= 0x02 && tsBytes[2] <= 0x04)
        //TODO: throw! иногда летит непонятно что.
        //0000e87a241dffff
        //TODO: тут ещё max date прилетает в каком-то случае, если или нет данных или ошибка?
        
        //        let timeUint64_ = UInt64([0x00, 0x00, 0x02, 0x00,  0x00,0x00,0x00,0x00])
        //        let unixTimestamp_ = Int(timeUint64_) - 2208988800000
        //        let ts_ = Date(timeIntervalSince1970: TimeInterval(Double(unixTimestamp_) / 1_000))
        //        print(ts_.toLocalString())
        //
        //        let timeUint64__ = UInt64([0x00, 0x00, 0x04, 0xFF,  0x00,0x00,0x00,0x00])
        //        let unixTimestamp__ = Int(timeUint64__) - 2208988800000
        //        let ts__ = Date(timeIntervalSince1970: TimeInterval(Double(unixTimestamp__) / 1_000))
        //        print(ts__.toLocalString())
        
        //let prerollByte = 1
        let payloadOffset = tsOffset + tsLen //+ prerollByte
        let payload = data.suffix(from: payloadOffset)
        
        return MediaStream.Frame(streamId: streamId, ts: ts, isSubtitles: isSubtitles, payload: payload)
    }
}

extension Data {
    func object<T>(at index: Index) -> T {
        subdata(in: index ..< index.advanced(by: MemoryLayout<T>.size))
            .withUnsafeBytes { $0.load(as: T.self) }
    }
}

extension Data {
    func copyBytes<T>(as _: T.Type) -> [T] {
        return withUnsafeBytes { (bytes: UnsafePointer<T>) in
            Array(UnsafeBufferPointer(start: bytes, count: count / MemoryLayout<T>.stride))
        }
    }
}

let sample = """
[
  {
    "endpoint": "DEMOSERVER/DeviceIpint.4/SourceEndpoint.video:0:0",
    "format": "jpeg",
    "method": "play",
    "streamId": "11aa89aa-3f62-b403-b0e5-10943df7b0f7",
    "keyFrames": false,
    "speed": 0,
    "archive": "DEMOSERVER/MultimediaStorage.AliceBlue/MultimediaStorage",
    "width": 1024,
    "height": 0,
    "vc": 3,
    "beginTime": "20240418T090649.651"
  },
  {
    "method": "stop",
    "streamId": "11aa89aa-3f62-b403-b0e5-10943df7b0f7"
  },
  {
    "endpoint": "DEMOSERVER/DeviceIpint.4/SourceEndpoint.video:0:0",
    "format": "mp4",
    "method": "play",
    "streamId": "2350b199-dfc1-7d64-6099-e8c093484cd6",
    "keyFrames": false,
    "speed": 1,
    "beginTime": "20240418T090649.651",
    "archive": "DEMOSERVER/MultimediaStorage.AliceBlue/MultimediaStorage"
  },
  {
    "endpoint": "DEMOSERVER/DeviceIpint.1/SourceEndpoint.video:0:0",
    "format": "mp4",
    "method": "play",
    "streamId": "1a42be18-f3f1-5e70-444e-194d767a9dba",
    "keyFrames": false,
    "speed": 1
  }
]
"""

/// https://stackoverflow.com/questions/32769929/convert-bytes-uint8-array-to-int-in-swift
public extension UnsignedInteger {
    init(_ bytes: [UInt8]) {
        precondition(bytes.count <= MemoryLayout<Self>.size)

        var value: UInt64 = 0

        for byte in bytes {
            value <<= 8
            value |= UInt64(byte)
        }

        self.init(value)
    }
}
