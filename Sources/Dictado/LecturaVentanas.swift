import AppKit
import ApplicationServices
import ScreenCaptureKit

/// Lecturas del sistema que comparten las ventanas flotantes del Dock y el selector de apps (⌘Tab): correr un guion de AppleScript,
/// el marco de una ventana por Accesibilidad y una miniatura por ventana con ScreenCaptureKit (solo con el permiso ya dado).
enum LecturaVentanas {
    nonisolated static func ejecutar(_ guion: String) -> String? {
        var error: NSDictionary?
        let r = NSAppleScript(source: guion)?.executeAndReturnError(&error)
        return error == nil ? r?.stringValue : nil
    }

    static func marco(_ w: AXUIElement?) -> CGRect? {
        guard let w else { return nil }
        var p: CFTypeRef?, s: CFTypeRef?
        guard AXUIElementCopyAttributeValue(w, kAXPositionAttribute as CFString, &p) == .success,
              AXUIElementCopyAttributeValue(w, kAXSizeAttribute as CFString, &s) == .success,
              let pv = p, let sv = s else { return nil }
        var pt = CGPoint.zero, sz = CGSize.zero
        AXValueGetValue(pv as! AXValue, .cgPoint, &pt)
        AXValueGetValue(sv as! AXValue, .cgSize, &sz)
        return CGRect(origin: pt, size: sz)
    }

    /// Una miniatura por ventana (en el orden de `marcos`), emparejando por el marco. Solo con el permiso ya dado.
    static func miniaturas(pid: pid_t, marcos: [CGRect?]) async -> [NSImage?] {
        guard let contenido = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) else { return marcos.map { _ in nil } }
        let suyas = contenido.windows.filter { $0.owningApplication?.processID == pid && $0.frame.width > 40 }
        var resultado: [NSImage?] = []
        for m in marcos {
            guard let m, let w = suyas.min(by: { distancia($0.frame, m) < distancia($1.frame, m) }), distancia(w.frame, m) < 12 else { resultado.append(nil); continue }
            let c = SCStreamConfiguration()
            let k = min(1, 320 / max(1, w.frame.width))
            c.width = Int(w.frame.width * k * 2)
            c.height = Int(w.frame.height * k * 2)
            c.showsCursor = false
            let f = SCContentFilter(desktopIndependentWindow: w)
            if let cg = try? await SCScreenshotManager.captureImage(contentFilter: f, configuration: c) {
                resultado.append(NSImage(cgImage: cg, size: NSSize(width: cg.width / 2, height: cg.height / 2)))
            } else { resultado.append(nil) }
        }
        return resultado
    }

    private static func distancia(_ a: CGRect, _ b: CGRect) -> CGFloat {
        abs(a.minX - b.minX) + abs(a.minY - b.minY) + abs(a.width - b.width) + abs(a.height - b.height)
    }
}
