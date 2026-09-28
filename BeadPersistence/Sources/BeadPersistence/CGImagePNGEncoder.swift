import CoreGraphics
import Foundation
import ImageIO

/// PNG encoding via ImageIO, which is available on both iOS and macOS without pulling in
/// UIKit/AppKit — keeps this package's test target buildable on macOS while producing PNG
/// data identical to what the shipped iOS app will use.
enum CGImagePNGEncoder {
    static func encode(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
