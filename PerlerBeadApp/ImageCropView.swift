import SwiftUI

/// A square crop view: the source image fills the crop frame (aspect-fill) and the user can
/// drag to reposition which part of the image is visible inside the fixed square frame.
/// Produces a cropped UIImage clipped to that square when `onConfirm` is invoked.
struct ImageCropView: View {
    let sourceImage: UIImage
    let onConfirm: (UIImage) -> Void
    let onCancel: () -> Void

    @State private var offset: CGSize = .zero
    @State private var dragStart: CGSize = .zero

    private let cropSize: CGFloat = 320

    var body: some View {
        VStack(spacing: 24) {
            Text("拖动调整取景范围")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)

            GeometryReader { geometry in
                let fillSize = aspectFillSize(imageSize: sourceImage.size, boundingSize: CGSize(width: cropSize, height: cropSize))
                ZStack {
                    Color.black
                    Image(uiImage: sourceImage)
                        .resizable()
                        .frame(width: fillSize.width, height: fillSize.height)
                        .offset(offset)
                }
                .frame(width: cropSize, height: cropSize)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppTheme.coral, lineWidth: 3)
                )
                .position(x: geometry.size.width / 2, y: cropSize / 2)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            offset = CGSize(
                                width: dragStart.width + value.translation.width,
                                height: dragStart.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            dragStart = offset
                        }
                )
            }
            .frame(height: cropSize)

            HStack(spacing: 16) {
                Button("取消", action: onCancel)
                    .buttonStyle(.bordered)
                Button("确定") {
                    let cropped = renderCroppedImage()
                    onConfirm(cropped)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.coral)
                .accessibilityIdentifier("confirmCropButton")
            }
        }
        .padding()
    }

    private func aspectFillSize(imageSize: CGSize, boundingSize: CGSize) -> CGSize {
        let scale = max(boundingSize.width / imageSize.width, boundingSize.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    /// Renders the currently visible square crop region to a new UIImage at the source image's
    /// native resolution (scaled proportionally), so downstream processing works from full detail
    /// rather than the small on-screen preview size.
    private func renderCroppedImage() -> UIImage {
        let fillSize = aspectFillSize(imageSize: sourceImage.size, boundingSize: CGSize(width: cropSize, height: cropSize))
        let scaleToNative = sourceImage.size.width / fillSize.width

        // Everything up to here is in "points" (UIImage.size is points, not pixels), but
        // CGImage.cropping(to:) operates on the backing CGImage's pixel buffer. On any Retina
        // device (scale 2x/3x, i.e. virtually every real iPhone) skipping this conversion crops
        // the wrong region entirely — e.g. on a 3x image it only ever sees the top-left third.
        let cropOriginInNativePoints = CGPoint(
            x: (fillSize.width - cropSize) / 2 - offset.width,
            y: (fillSize.height - cropSize) / 2 - offset.height
        )
        let pixelScale = sourceImage.scale
        let cropRectInPixelSpace = CGRect(
            x: cropOriginInNativePoints.x * scaleToNative * pixelScale,
            y: cropOriginInNativePoints.y * scaleToNative * pixelScale,
            width: cropSize * scaleToNative * pixelScale,
            height: cropSize * scaleToNative * pixelScale
        ).intersection(CGRect(
            x: 0, y: 0,
            width: sourceImage.size.width * pixelScale,
            height: sourceImage.size.height * pixelScale
        ))

        guard let cgImage = sourceImage.cgImage?.cropping(to: cropRectInPixelSpace) else {
            return sourceImage
        }
        return UIImage(cgImage: cgImage, scale: pixelScale, orientation: sourceImage.imageOrientation)
    }
}
