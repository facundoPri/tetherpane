import CoreImage
import SwiftUI

struct WirelessQRCodeView: View {
    let payload: String

    var body: some View {
        if let image = makeImage() {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .padding(14)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
                .frame(width: 240, height: 240)
                .accessibilityLabel("Wireless Debugging pairing QR code")
        } else {
            ContentUnavailableView(
                "QR code unavailable",
                systemImage: "qrcode",
                description: Text("Cancel and generate a new pairing code.")
            )
            .frame(width: 240, height: 240)
        }
    }

    private func makeImage() -> CGImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
            return nil
        }
        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let outputImage = filter.outputImage?.transformed(
            by: CGAffineTransform(scaleX: 10, y: 10)
        ) else {
            return nil
        }
        return CIContext(options: nil).createCGImage(outputImage, from: outputImage.extent)
    }
}
