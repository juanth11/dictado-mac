import Foundation

// La lógica pura de los fondos de macOS que un espacio puede pedir con `fondo:`: encontrar un fondo de sistema por su nombre entre los
// archivos que hay en el Mac, leer el catálogo de aéreos animados (`entries.json` de idleassetsd), elegir uno por nombre o identificador
// y escoger el cuadro más bonito de un video. Sin AppKit ni AVFoundation: lo que toca el disco y el video vive en `FondoAereo.swift`.

// MARK: - Aéreos

/// Un aéreo del catálogo de macOS (la lista que Ajustes del Sistema muestra en Salvapantallas y Fondo de pantalla).
public struct AereoMac: Equatable, Sendable {
    public var id: String
    /// "Patagonia", "Yosemite", "Hong Kong"…
    public var nombre: String
    /// Paisajes, Ciudades, Bajo el agua o Espacio.
    public var categoria: String
    /// Su orden dentro del catálogo (menor = antes).
    public var orden: Int

    public init(id: String, nombre: String, categoria: String, orden: Int) {
        self.id = id
        self.nombre = nombre
        self.categoria = categoria
        self.orden = orden
    }
}

public enum CatalogoFondos {
    // MARK: Leer el catálogo

    /// Lee `entries.json`: id, nombre (`accessibilityLabel`), categoría y orden. Un archivo roto da una lista vacía.
    public static func aereos(json: String) -> [AereoMac] {
        guard let datos = json.data(using: .utf8),
              let raiz = try? JSONSerialization.jsonObject(with: datos) as? [String: Any],
              let assets = raiz["assets"] as? [[String: Any]] else { return [] }
        var nombresCategoria: [String: String] = [:]
        for c in raiz["categories"] as? [[String: Any]] ?? [] {
            if let id = c["id"] as? String, let clave = c["localizedNameKey"] as? String { nombresCategoria[id] = categoria(clave) }
        }
        var salida: [AereoMac] = []
        for a in assets {
            guard let id = a["id"] as? String, let nombre = a["accessibilityLabel"] as? String, !nombre.isEmpty else { continue }
            let cat = (a["categories"] as? [String])?.first.flatMap { nombresCategoria[$0] } ?? ""
            salida.append(AereoMac(id: id, nombre: nombre, categoria: cat, orden: a["preferredOrder"] as? Int ?? Int.max))
        }
        return salida
    }

    /// "AerialCategoryLandscapes" → "Paisajes".
    public static func categoria(_ clave: String) -> String {
        switch clave {
        case "AerialCategoryLandscapes": return "Paisajes"
        case "AerialCategoryCities": return "Ciudades"
        case "AerialCategoryUnderwater": return "Bajo el agua"
        case "AerialCategorySpace": return "Espacio"
        default: return clave.replacingOccurrences(of: "AerialCategory", with: "")
        }
    }

    // MARK: Elegir un aéreo

    /// Palabras que se pueden escribir para pedir "uno de montañas nevadas": se prueban estos nombres, en este orden.
    static let alias: [String: [String]] = [
        "nevado": ["Patagonia", "Greenland", "Iceland"], "nevados": ["Patagonia", "Greenland", "Iceland"],
        "nevada": ["Patagonia", "Greenland", "Iceland"], "nevadas": ["Patagonia", "Greenland", "Iceland"],
        "nieve": ["Patagonia", "Greenland", "Iceland"], "montanas nevadas": ["Patagonia", "Greenland", "Iceland"],
    ]

    /// El aéreo que pide `consulta`: por identificador (completo o su comienzo, mínimo 6 letras), por nombre exacto (sin importar
    /// mayúsculas ni tildes), por alias ("nevadas") o por nombre que la contenga. Con varios del mismo nombre gana el que ya está
    /// descargado y, entre iguales, el de menor orden: así "Patagonia" es la que tiene el `.mov` en el Mac.
    public static func elegirAereo(_ consulta: String, entre todos: [AereoMac], descargados: Set<String>) -> AereoMac? {
        let q = BusquedaApps.normalizar(consulta)
        guard !q.isEmpty else { return nil }
        func mejor(_ candidatos: [AereoMac]) -> AereoMac? {
            candidatos.min { a, b in
                let da = descargados.contains(a.id), db = descargados.contains(b.id)
                if da != db { return da }
                return a.orden != b.orden ? a.orden < b.orden : a.id < b.id
            }
        }
        let id = q.uppercased()
        if id.count >= 6, let porId = mejor(todos.filter { $0.id.hasPrefix(id) }) { return porId }
        if let exacto = mejor(todos.filter { BusquedaApps.normalizar($0.nombre) == q }) { return exacto }
        for nombre in alias[q] ?? [] {
            if let a = mejor(todos.filter { BusquedaApps.normalizar($0.nombre) == BusquedaApps.normalizar(nombre) }) { return a }
        }
        return mejor(todos.filter { BusquedaApps.normalizar($0.nombre).contains(q) })
    }

    // MARK: Fondos de sistema por nombre

    static let extensionesImagen = ["heic", "jpg", "jpeg", "png"]

    /// Entre las rutas de archivos de fondo que hay en el Mac, la de `nombre` ("Sonoma", "iMac Orange", "sonoma horizon"). Compara el
    /// nombre del archivo sin extensión: exacto primero; si no, el único que empiece con ese texto; si no, el que lo contenga. Las
    /// miniaturas (`.thumbnails`) y lo que no es imagen no cuentan. Con repetidos gana la ruta más corta y la extensión HEIC.
    public static func elegirSistema(_ nombre: String, entre rutas: [String]) -> String? {
        var q = BusquedaApps.normalizar(nombre)
        for e in extensionesImagen where q.hasSuffix("." + e) { q = String(q.dropLast(e.count + 1)) }
        guard !q.isEmpty else { return nil }
        let candidatas: [(clave: String, ruta: String)] = rutas.compactMap { r in
            let url = URL(fileURLWithPath: r)
            guard extensionesImagen.contains(url.pathExtension.lowercased()), !r.contains("/.thumbnails/") else { return nil }
            return (BusquedaApps.normalizar(url.deletingPathExtension().lastPathComponent), r)
        }
        func mejor(_ a: [(clave: String, ruta: String)]) -> String? {
            a.min { x, y in
                let ex = extensionesImagen.firstIndex(of: URL(fileURLWithPath: x.ruta).pathExtension.lowercased()) ?? 9
                let ey = extensionesImagen.firstIndex(of: URL(fileURLWithPath: y.ruta).pathExtension.lowercased()) ?? 9
                if x.ruta.count != y.ruta.count { return x.ruta.count < y.ruta.count }
                return ex != ey ? ex < ey : x.ruta < y.ruta
            }?.ruta
        }
        if let exacto = mejor(candidatas.filter { $0.clave == q }) { return exacto }
        let empieza = candidatas.filter { $0.clave.hasPrefix(q) }
        if let corto = empieza.map(\.clave.count).min(), let r = mejor(empieza.filter { $0.clave.count == corto }) { return r }
        return mejor(candidatas.filter { $0.clave.contains(q) })
    }

    /// El nombre del archivo (en `fondos/`) donde se guarda el cuadro fijo de un aéreo: "patagonia", "hong-kong".
    public static func nombreDeCuadro(_ aereo: AereoMac) -> String {
        let base = BusquedaApps.normalizar(aereo.nombre).map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let limpio = String(base).split(separator: "-").joined(separator: "-")
        return (limpio.isEmpty ? "aereo" : limpio) + "-" + String(aereo.id.prefix(8)).lowercased()
    }

    // MARK: El cuadro más bonito

    /// De varios cuadros de un video (su luminancia media y su contraste, 0 a 1), el índice del mejor para un fondo fijo: con contraste
    /// (detalle: montañas, no cielo liso) y ni quemado ni oscuro (luminancia cerca del 45 %).
    public static func cuadroBonito(luminancias: [Double], contrastes: [Double]) -> Int? {
        guard !luminancias.isEmpty, luminancias.count == contrastes.count else { return nil }
        func puntos(_ i: Int) -> Double { contrastes[i] - 1.2 * abs(luminancias[i] - 0.45) }
        return luminancias.indices.max { puntos($0) < puntos($1) }
    }
}
