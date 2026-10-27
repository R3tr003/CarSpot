// CLI della pipeline: scontorna l'auto (Vision), sfoca le targhe, salva PNG trasparente ritagliato.
// Uso: cutout <cartella_in> <cartella_out>. Salta i file già fatti. Una riga di esito per file.
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import Vision

let args = CommandLine.arguments
guard args.count == 3 else { print("uso: cutout <in> <out>"); exit(2) }
let inDir = URL(fileURLWithPath: args[1]), outDir = URL(fileURLWithPath: args[2])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let ctx = CIContext()
let minCoverage = 0.08   // soggetto troppo piccolo = foto inutilizzabile

/// Frazione dell'immagine coperta da una maschera (media del canale).
func coverage(_ mask: CVPixelBuffer) -> Double {
    let ci = CIImage(cvPixelBuffer: mask)
    let avg = CIFilter.areaAverage()
    avg.inputImage = ci
    avg.extent = ci.extent
    var px = [UInt8](repeating: 0, count: 4)
    ctx.render(avg.outputImage!, toBitmap: &px, rowBytes: 4,
               bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
    return Double(px[0]) / 255
}

/// Testo che sembra una targa: 5–8 caratteri alfanumerici con lettere e cifre.
func looksLikePlate(_ s: String) -> Bool {
    let t = s.uppercased().filter { $0.isLetter || $0.isNumber }
    guard (4...10).contains(t.count) else { return false }
    return t.contains(where: \.isLetter) && t.contains(where: \.isNumber)
}

/// Riquadri (normalizzati, origine in basso a sinistra) che sembrano targhe.
func plateBoxes(_ cg: CGImage) -> [CGRect] {
    let ocr = VNRecognizeTextRequest()
    ocr.recognitionLevel = .accurate
    ocr.usesLanguageCorrection = false
    ocr.minimumTextHeight = 0.01
    let rects = VNDetectTextRectanglesRequest()
    try? VNImageRequestHandler(cgImage: cg).perform([ocr, rects])
    var boxes = (ocr.results ?? []).filter { obs in
        obs.topCandidates(3).contains { looksLikePlate($0.string) }
    }.map(\.boundingBox)
    // Targhe illeggibili: righe di testo basse e larghe nella metà inferiore della foto.
    let aspect = CGFloat(cg.width) / CGFloat(cg.height)
    for r in (rects.results ?? []).map(\.boundingBox) {
        let ratio = (r.width * aspect) / max(r.height, 0.0001)
        if (2.2...7).contains(ratio), r.height < 0.12, r.midY < 0.6,
           !boxes.contains(where: { $0.intersects(r) }) {
            boxes.append(r)
        }
    }
    return boxes
}

/// Sfoca le targhe sull'immagine intera, prima dello scontorno.
func blurPlates(_ cg: CGImage) -> (CGImage, Int) {
    let boxes = plateBoxes(cg)
    guard !boxes.isEmpty else { return (cg, 0) }
    let image = CIImage(cgImage: cg)
    let blurred = image.clampedToExtent().applyingGaussianBlur(sigma: 14).cropped(to: image.extent)
    var result = image
    let w = image.extent.width, h = image.extent.height
    for b in boxes {
        let r = CGRect(x: b.minX * w, y: b.minY * h, width: b.width * w, height: b.height * h)
            .insetBy(dx: -b.width * w * 0.2, dy: -b.height * h * 0.35)
        let blend = CIFilter.blendWithMask()
        blend.inputImage = blurred
        blend.backgroundImage = result
        blend.maskImage = CIImage(color: .white).cropped(to: r)
        result = blend.outputImage!.cropped(to: image.extent)
    }
    guard let out = ctx.createCGImage(result, from: image.extent) else { return (cg, 0) }
    return (out, boxes.count)
}

let files = (try? FileManager.default.contentsOfDirectory(at: inDir, includingPropertiesForKeys: nil)) ?? []
for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
    let name = file.deletingPathExtension().lastPathComponent
    let out = outDir.appendingPathComponent(name + ".png")
    if FileManager.default.fileExists(atPath: out.path) { continue }
    guard let src = CGImageSourceCreateWithURL(file as CFURL, nil),
          let cg = CGImageSourceCreateImageAtIndex(src, 0,
                    [kCGImageSourceShouldAllowFloat: false] as CFDictionary) else {
        print("\(name)\tillegibile"); continue
    }
    autoreleasepool {
        let (clean, plates) = blurPlates(cg)
        let req = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: clean)
        do {
            try handler.perform([req])
            guard let obs = req.results?.first, !obs.allInstances.isEmpty else {
                print("\(name)\tsenza_soggetto"); return
            }
            var best = obs.allInstances.first!, bestCov = -1.0
            for inst in obs.allInstances {
                let m = try obs.generateScaledMaskForImage(forInstances: [inst], from: handler)
                let c = coverage(m)
                if c > bestCov { bestCov = c; best = inst }
            }
            guard bestCov >= minCoverage else { print("\(name)\tsoggetto_piccolo"); return }
            let buf = try obs.generateMaskedImage(ofInstances: [best], from: handler, croppedToInstancesExtent: true)
            try ctx.writePNGRepresentation(of: CIImage(cvPixelBuffer: buf), to: out, format: .RGBA8,
                                           colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
            print("\(name)\tok\t\(plates)")
        } catch {
            print("\(name)\terrore\t\(error.localizedDescription)")
        }
    }
}
