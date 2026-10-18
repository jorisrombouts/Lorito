// Generates the app icon: a parrot head drawn as waveform bars, Apple system orange, Tahoe icon recipe
// (light tint to full colour, white glyph, a darker shade of the same colour for depth).
// Rebuild Resources/AppIcon.icns with:
//   swiftc -O make-icon.swift -o /tmp/icon && /tmp/icon /tmp/icon1024.png
//   mkdir -p /tmp/AppIcon.iconset && for s in 16 32 128 256 512; do sips -z $s $s /tmp/icon1024.png --out /tmp/AppIcon.iconset/icon_${s}x${s}.png; sips -z $((s*2)) $((s*2)) /tmp/icon1024.png --out /tmp/AppIcon.iconset/icon_${s}x${s}@2x.png; done
//   iconutil -c icns /tmp/AppIcon.iconset -o Resources/AppIcon.icns
import SwiftUI
import AppKit

func mix(_ c: NSColor, _ with: NSColor, _ f: CGFloat) -> Color { Color(nsColor: c.blended(withFraction: f, of: with)!) }
let hue = NSColor.systemOrange

// Head and neck, unit square; the beak is drawn solid on top so the hook reads through the bars.
func parrotBody(_ s: CGFloat) -> Path {
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
    var path = Path()
    path.addEllipse(in: CGRect(x: 0.10 * s, y: 0.15 * s, width: 0.66 * s, height: 0.66 * s))
    path.move(to: p(0.14, 0.60)); path.addQuadCurve(to: p(0.08, 0.96), control: p(0.02, 0.80)); path.addLine(to: p(0.72, 0.96)); path.addQuadCurve(to: p(0.70, 0.62), control: p(0.78, 0.82)); path.closeSubpath()
    return path
}
func parrotBeak(_ s: CGFloat) -> Path {
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
    var path = Path()
    path.move(to: p(0.62, 0.30)); path.addQuadCurve(to: p(0.98, 0.46), control: p(0.92, 0.26)); path.addQuadCurve(to: p(0.86, 0.70), control: p(1.00, 0.62)); path.addQuadCurve(to: p(0.72, 0.56), control: p(0.82, 0.58)); path.addQuadCurve(to: p(0.62, 0.30), control: p(0.66, 0.44)); path.closeSubpath()
    path.move(to: p(0.70, 0.58)); path.addQuadCurve(to: p(0.86, 0.72), control: p(0.82, 0.60)); path.addQuadCurve(to: p(0.68, 0.72), control: p(0.78, 0.78)); path.closeSubpath()
    return path
}

struct Parrot: View {
    let bars = 11
    var body: some View {
        Canvas { ctx, size in
            let s = size.width
            let body = parrotBody(s)
            let pitch = 0.72 * s / CGFloat(bars)
            let w = pitch * 0.58
            for i in 0..<bars {   // one rounded bar per column, its ends on the silhouette
                let x = 0.06 * s + pitch * (CGFloat(i) + 0.5)
                var top: CGFloat? = nil, bottom: CGFloat = 0
                var y: CGFloat = 0
                while y <= s { if body.contains(CGPoint(x: x, y: y)) { if top == nil { top = y }; bottom = y }; y += 2 }
                guard let t = top else { continue }
                var bar = Path(); bar.addRoundedRect(in: CGRect(x: x - w / 2, y: t, width: w, height: max(bottom - t, w)), cornerSize: CGSize(width: w / 2, height: w / 2))
                ctx.fill(bar, with: .color(.white))
            }
            ctx.fill(parrotBeak(s), with: .color(mix(hue, .black, 0.45)))
            var eye = Path(); eye.addEllipse(in: CGRect(x: 0.47 * s, y: 0.37 * s, width: 0.12 * s, height: 0.12 * s))
            ctx.fill(eye, with: .color(mix(hue, .black, 0.05)))
        }
    }
}

struct Icon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 184, style: .continuous)   // Apple macOS icon grid: 824 pt square, 184 pt corners
                .fill(LinearGradient(colors: [mix(hue, .white, 0.30), mix(hue, .black, 0.10)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 184, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0)], startPoint: .top, endPoint: .center)))
                .overlay(RoundedRectangle(cornerRadius: 184, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 4))
                .shadow(color: .black.opacity(0.25), radius: 20, y: 12)
            Parrot()
                .frame(width: 680, height: 680)
                .offset(x: -30, y: 90)
                .shadow(color: .black.opacity(0.25), radius: 14, y: 10)
        }
        .padding(100)
        .frame(width: 1024, height: 1024)
    }
}

MainActor.assumeIsolated {
let r = ImageRenderer(content: Icon())
r.scale = 1
let img = r.nsImage!
let png = NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("wrote", CommandLine.arguments[1])
}
