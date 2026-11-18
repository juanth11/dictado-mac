import Foundation

/// Un archivo o carpeta dentro de una carpeta del Dock.
public struct ArchivoReciente: Equatable, Sendable, Identifiable {
    public var nombre: String
    public var ruta: String
    public var modificado: Date
    public var esCarpeta: Bool
    public var id: String { ruta }

    public init(nombre: String, ruta: String, modificado: Date, esCarpeta: Bool = false) {
        self.nombre = nombre
        self.ruta = ruta
        self.modificado = modificado
        self.esCarpeta = esCarpeta
    }
}

public enum CarpetaDock {
    /// Cuántos elementos lista el panel de una carpeta, como mucho.
    public static let maximo = 40
    public static let columnas = 5

    /// Lo más recién modificado primero (a igual fecha, por nombre), sin los ocultos (los que empiezan por punto), con tope.
    public static func masRecientes(_ entradas: [ArchivoReciente], maximo: Int = CarpetaDock.maximo) -> [ArchivoReciente] {
        guard maximo > 0 else { return [] }
        let visibles = entradas.filter { !$0.nombre.hasPrefix(".") && !$0.nombre.isEmpty }
        let ordenadas = visibles.sorted {
            if $0.modificado != $1.modificado { return $0.modificado > $1.modificado }
            return BusquedaApps.normalizar($0.nombre) < BusquedaApps.normalizar($1.nombre)
        }
        return Array(ordenadas.prefix(maximo))
    }

    public static func filas(_ cuantos: Int, columnas: Int = CarpetaDock.columnas) -> Int {
        guard cuantos > 0, columnas > 0 else { return 0 }
        return (cuantos + columnas - 1) / columnas
    }

    /// Las filas que se ven a la vez en el panel (el resto se desplaza).
    public static let filasVisibles = 3

    /// El nombre de la carpeta como lo dice el sello del mosaico: en mayúsculas, sin pasarse de `maximo` letras.
    public static func sello(_ ruta: String, maximo: Int = 12) -> String {
        let nombre = (ruta as NSString).lastPathComponent
        let limpio = (nombre.isEmpty ? ruta : nombre).uppercased()
        return limpio.count > maximo ? String(limpio.prefix(maximo - 1)) + "…" : limpio
    }

    /// La fecha de modificación en palabras cortas para el pie de cada miniatura: "ahora", "hace 5 min", "hace 3 h", "ayer",
    /// "hace 4 d".
    public static func hace(_ fecha: Date, ahora: Date) -> String {
        let s = Int(ahora.timeIntervalSince(fecha))
        if s < 60 { return "ahora" }
        if s < 3600 { return "hace \(s / 60) min" }
        if s < 24 * 3600 { return "hace \(s / 3600) h" }
        if s < 48 * 3600 { return "ayer" }
        return "hace \(s / 86_400) d"
    }
}
