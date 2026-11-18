import Foundation

/// La última grabación de reunión, siempre al alcance: `ultima.md` apunta a su transcripción y `ultima-notas.md` a su nota (en el inbox
/// del cerebro). Así "revisa la transcripción de lo que acabo de grabar" tiene una sola ruta fija. Solo toca enlaces dentro de la carpeta
/// de reuniones de Dictado; no lee ni escribe nada más.
public enum UltimaGrabacion {
    public struct Rutas: Equatable, Sendable {
        public var transcripcion: String?
        public var notas: String?
        /// Los enlaces estables en la carpeta de reuniones.
        public var enlaceTranscripcion: String
        public var enlaceNotas: String
    }

    public static let nombreTranscripcion = "ultima.md"
    public static let nombreNotas = "ultima-notas.md"

    /// La transcripción más reciente de la carpeta: `<AAAAMMDDHHmm>-<slug>.md`, sin contar los enlaces `ultima*.md`. Manda la marca de
    /// tiempo del nombre (cuándo empezó la grabación); sin marca, la fecha de modificación.
    public static func transcripcionMasReciente(en carpeta: URL) -> URL? {
        let fm = FileManager.default
        let archivos = (try? fm.contentsOfDirectory(at: carpeta, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let candidatos = archivos.filter { $0.pathExtension == "md" && !$0.lastPathComponent.hasPrefix("ultima") }
        func marca(_ u: URL) -> String {
            let n = u.lastPathComponent
            let digitos = n.prefix(12)
            return digitos.count == 12 && digitos.allSatisfy(\.isNumber) ? String(digitos) : ""
        }
        func modificado(_ u: URL) -> Date { (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast }
        return candidatos.max { a, b in
            let ma = marca(a), mb = marca(b)
            if ma != mb { return ma < mb }
            return modificado(a) < modificado(b)
        }
    }

    /// La nota del inbox (`reunion-*.md`) cuyo frontmatter dice `transcripcion: <ruta>` de esa transcripción. Si hay varias, la más nueva.
    public static func notaDe(transcripcion: URL, inbox: URL) -> URL? {
        let fm = FileManager.default
        let objetivo = transcripcion.resolvingSymlinksInPath().standardizedFileURL.path
        let archivos = (try? fm.contentsOfDirectory(at: inbox, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        var mejor: (url: URL, fecha: Date)?
        for a in archivos where a.pathExtension == "md" && a.lastPathComponent.hasPrefix("reunion-") {
            guard let ruta = rutaDeTranscripcion(en: a),
                  URL(fileURLWithPath: ruta).resolvingSymlinksInPath().standardizedFileURL.path == objetivo else { continue }
            let f = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if mejor == nil || f > mejor!.fecha { mejor = (a, f) }
        }
        return mejor?.url
    }

    /// El valor de `transcripcion:` en el frontmatter (solo se leen los primeros 8 KB).
    static func rutaDeTranscripcion(en nota: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: nota) else { return nil }
        defer { try? h.close() }
        let texto = String(decoding: (try? h.read(upToCount: 8192)) ?? Data(), as: UTF8.self)
        guard texto.hasPrefix("---") else { return nil }
        for linea in texto.split(separator: "\n", omittingEmptySubsequences: false).dropFirst() {
            if linea.hasPrefix("---") { break }
            guard linea.hasPrefix("transcripcion:") else { continue }
            let v = linea.dropFirst("transcripcion:".count).trimmingCharacters(in: .whitespaces)
            return v.isEmpty ? nil : v.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return nil
    }

    /// Busca la última grabación y deja los dos enlaces al día (el de la nota se quita si ya no hay nota). `nota` fuerza una nota conocida
    /// (la que acaba de crear el cerebro). Devuelve las rutas; sin ninguna transcripción, nil (y los enlaces viejos se quitan).
    @discardableResult
    public static func actualizar(carpeta: URL, inbox: URL?, nota: URL? = nil) -> Rutas? {
        let fm = FileManager.default
        let enlaceT = carpeta.appendingPathComponent(nombreTranscripcion), enlaceN = carpeta.appendingPathComponent(nombreNotas)
        guard let trans = transcripcionMasReciente(en: carpeta) else {
            quitar(enlaceT)
            quitar(enlaceN)
            return nil
        }
        let n = nota.flatMap { fm.fileExists(atPath: $0.path) ? $0 : nil } ?? inbox.flatMap { notaDe(transcripcion: trans, inbox: $0) }
        apuntar(enlaceT, a: trans)
        if let n { apuntar(enlaceN, a: n) } else { quitar(enlaceN) }
        return Rutas(transcripcion: trans.path, notas: n?.path, enlaceTranscripcion: enlaceT.path, enlaceNotas: enlaceN.path)
    }

    private static func quitar(_ enlace: URL) {
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: enlace.path)) != nil { try? FileManager.default.removeItem(at: enlace) }
    }

    /// Un enlace simbólico (si ya apunta ahí, no se toca). Si en su lugar hay un archivo de verdad, tampoco: no se pisa lo que no es nuestro.
    private static func apuntar(_ enlace: URL, a destino: URL) {
        let fm = FileManager.default
        if let actual = try? fm.destinationOfSymbolicLink(atPath: enlace.path) {
            if actual == destino.path { return }
            try? fm.removeItem(at: enlace)
        } else if fm.fileExists(atPath: enlace.path) {
            return
        }
        try? fm.createSymbolicLink(atPath: enlace.path, withDestinationPath: destino.path)
    }

    /// Lo que imprime `--ultima-grabacion`.
    public static func texto(_ r: Rutas?) -> String {
        guard let r else { return "sin grabaciones todavía" }
        return ["transcripción: " + (r.transcripcion ?? "-"), "notas: " + (r.notas ?? "sin notas todavía"),
                "enlace estable: " + r.enlaceTranscripcion].joined(separator: "\n")
    }

    /// Lo que imprime `--ultima-grabacion --json`.
    public static func json(_ r: Rutas?) -> String {
        var d: [String: Any] = ["hay": r != nil]
        if let r {
            d["transcripcion"] = r.transcripcion ?? NSNull()
            d["notas"] = r.notas ?? NSNull()
            d["enlaceTranscripcion"] = r.enlaceTranscripcion
            d["enlaceNotas"] = r.enlaceNotas
        }
        let datos = (try? JSONSerialization.data(withJSONObject: d, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
        return String(decoding: datos, as: UTF8.self)
    }
}
