import AppKit
import ApplicationServices
import DictadoKit
import os

private let log = Logger(subsystem: "app.dictado", category: "aprendiz")

/// Diccionario que aprende. Después de pegar un dictado, mira ese campo de texto hasta 90 s (cada 3 s, solo leyendo).
/// Si corriges una palabra que Dictado escribió mal, la corrección pasa a `correcciones.txt` (y el término a
/// `vocabulario.txt` si lleva mayúsculas), y vale desde el siguiente dictado.
/// - Un nombre o término ("lu mina" → "Lumina") se aprende a la primera; otra palabra, al verla corregida dos veces.
/// - Si corriges de vuelta algo que aprendió, lo olvida.
/// - Solo funciona en apps que muestran su texto a Accesibilidad (las nativas de Apple, Word, muchas otras);
///   en Chrome y algunas apps Electron no se ve el campo y no aprende nada.
/// Se apaga con `defaults write app.dictado aprender -bool NO` o desde el menú.
@MainActor
final class Aprendiz {
    /// (antes, después, olvidada): para avisar en la isla.
    var alAprender: ((String, String, Bool) -> Void)?

    private var campo: AXUIElement?
    private var pegado = ""
    private var valorAlPegar = ""
    private var ultimoTramo: String?
    private var reloj: Timer?
    private var inicio = Date()

    static var archivoPendientes: URL {
        Ajustes.archivoVocabulario.deletingLastPathComponent().appendingPathComponent("aprendizaje.json")
    }

    /// Recién pegado `texto`: empieza a mirar el campo (el ⌘V simulado tarda un momento en llegar).
    func observar(_ texto: String) {
        cerrar()
        guard Ajustes().aprender, !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        pegado = texto
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            MainActor.assumeIsolated { self?.empezar() }
        }
    }

    private func empezar() {
        guard let c = Self.campoEnfocado(), let v = Self.valor(c), v.contains(pegado) else { return }
        campo = c
        valorAlPegar = v
        inicio = Date()
        ultimoTramo = nil
        reloj = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.revisar() }
        }
    }

    private func leer() {
        guard let campo, let v = Self.valor(campo),
              let t = Aprendizaje.tramo(pegado: pegado, valorAlPegar: valorAlPegar, valorAhora: v) else { return }
        ultimoTramo = t
    }

    private func revisar() {
        guard let campo else { return }
        leer()
        let mismo = Self.campoEnfocado().map { CFEqual($0, campo) } ?? false
        if !mismo || Date().timeIntervalSince(inicio) > 90 { cerrar() }
    }

    /// Decide con lo último que se vio del campo: al irte a otro campo, a los 90 s o al empezar otro dictado.
    func cerrar() {
        reloj?.invalidate()
        reloj = nil
        guard campo != nil else { return }
        leer()
        defer {
            campo = nil
            ultimoTramo = nil
        }
        guard let t = ultimoTramo, t != pegado else { return }
        for c in Aprendizaje.cambios(pegado: pegado, editado: t) { registrar(c) }
    }

    // MARK: Guardar

    private func registrar(_ c: Aprendizaje.Cambio) {
        let correcciones = Ajustes().correcciones()
        func igual(_ a: String, _ b: String) -> Bool { a.caseInsensitiveCompare(b) == .orderedSame }
        // Corregiste de vuelta algo aprendido: estaba mal, se olvida.
        if let mala = correcciones.first(where: { $0.1 == c.antes && igual($0.0, c.despues) }) {
            Self.quitarCorreccion(mala)
            log.notice("olvidada: \(mala.0, privacy: .private) = \(mala.1, privacy: .private)")
            alAprender?(mala.0, mala.1, true)
            return
        }
        guard !correcciones.contains(where: { igual($0.0, c.antes) }) else { return }

        var vistos = (try? JSONDecoder().decode([String: Int].self, from: Data(contentsOf: Self.archivoPendientes))) ?? [:]
        let clave = "\(c.antes) = \(c.despues)"
        vistos[clave, default: 0] += 1
        let listo = c.seguro || vistos[clave, default: 0] >= 2
        if listo { vistos[clave] = nil }
        if let datos = try? JSONEncoder().encode(vistos) { try? datos.write(to: Self.archivoPendientes, options: .atomic) }
        guard listo else { return }

        let fecha = Date().formatted(.iso8601.year().month().day())
        Self.agregar("# aprendida \(fecha)\n\(clave)\n", a: Ajustes.archivoCorrecciones)
        if c.despues.contains(where: \.isUppercase),
           !Ajustes().vocabulario().contains(where: { igual($0, c.despues) }) {
            Self.agregar("\(c.despues)\n", a: Ajustes.archivoVocabulario)
        }
        log.notice("aprendida: \(clave, privacy: .private)")
        alAprender?(c.antes, c.despues, false)
    }

    private static func agregar(_ texto: String, a url: URL) {
        var actual = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        if !actual.isEmpty, !actual.hasSuffix("\n") { actual += "\n" }
        try? (actual + texto).write(to: url, atomically: true, encoding: .utf8)
    }

    private static func quitarCorreccion(_ par: (String, String)) {
        let url = Ajustes.archivoCorrecciones
        guard let texto = try? String(contentsOf: url, encoding: .utf8) else { return }
        let lineas = texto.components(separatedBy: "\n").filter { linea in
            let partes = linea.components(separatedBy: "=").map { $0.trimmingCharacters(in: .whitespaces) }
            return !(partes.count == 2 && partes[0] == par.0 && partes[1] == par.1)
        }
        try? lineas.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: Accesibilidad (solo lectura)

    static func campoEnfocado() -> AXUIElement? {
        let sistema = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(sistema, 0.3)
        var valor: CFTypeRef?
        guard AXUIElementCopyAttributeValue(sistema, kAXFocusedUIElementAttribute as CFString, &valor) == .success,
              let valor, CFGetTypeID(valor) == AXUIElementGetTypeID() else { return nil }
        return (valor as! AXUIElement)
    }

    /// El texto del campo. Nunca de un campo de contraseña ni de uno enorme.
    static func valor(_ e: AXUIElement) -> String? {
        AXUIElementSetMessagingTimeout(e, 0.3)
        var rol: CFTypeRef?
        AXUIElementCopyAttributeValue(e, kAXSubroleAttribute as CFString, &rol)
        if (rol as? String) == "AXSecureTextField" { return nil }
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, kAXValueAttribute as CFString, &v) == .success,
              let s = v as? String, s.utf16.count < 300_000 else { return nil }
        return s
    }
}
