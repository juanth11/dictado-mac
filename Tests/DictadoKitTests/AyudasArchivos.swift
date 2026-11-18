import Foundation
@testable import DictadoKit

// Sin `import Testing`: con las Command Line Tools, Foundation y Testing no pueden convivir en un mismo archivo.

/// Una carpeta nueva y vacía en /tmp.
func carpetaTemporal(_ nombre: String = "dictado-prueba") -> URL {
    // `realpath` (no `resolvingSymlinksInPath`, que quita el /private): así las rutas coinciden con las que devuelve el listado de la carpeta.
    let base = realpath(NSTemporaryDirectory(), nil).map { String(cString: $0) } ?? NSTemporaryDirectory()
    let u = URL(fileURLWithPath: base).appendingPathComponent(nombre + "-" + UUID().uuidString)
    try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

@discardableResult
func escribirArchivo(_ texto: String, _ carpeta: URL, _ nombre: String) -> URL {
    let u = carpeta.appendingPathComponent(nombre)
    try? texto.write(to: u, atomically: true, encoding: .utf8)
    return u
}

/// A dónde apunta un enlace simbólico (nil si no es un enlace o no existe).
func destinoDeEnlace(_ u: URL) -> String? { try? FileManager.default.destinationOfSymbolicLink(atPath: u.path) }

func existeArchivo(_ u: URL) -> Bool { FileManager.default.fileExists(atPath: u.path) }

func leerArchivo(_ u: URL) -> String { (try? String(contentsOf: u, encoding: .utf8)) ?? "" }

/// Una nota de reunión con su frontmatter.
func notaConTranscripcion(_ ruta: String) -> String {
    "---\nsource: dictado-notas\ndate: 2026-11-16T11:30-05:00\nreunion: Comité\ntranscripcion: \(ruta)\n---\n# Notas · Comité\n\nResumen.\n"
}
