import Foundation

/// Los atajos de Apple (la app Atajos): cómo se lee `shortcuts list`, cuáles aparecen en Inicio y qué se muestra si uno falla.
public enum AtajosSistema {
    public static let cuantosPorOmision = 6
    /// Lo máximo que se deja correr un atajo antes de cortarlo.
    public static let segundosLimite: Double = 60
    public static let segundosLista: Double = 8

    /// Una línea por atajo; sin vacías ni repetidas, en el orden en que llegan.
    public static func analizarLista(_ salida: String) -> [String] {
        var vistos = Set<String>()
        return salida.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && vistos.insert($0).inserted }
    }

    /// Los que aparecen en Inicio. `preferidos` (el ajuste `isla.atajos`): esos, en su orden y solo los que existen; si
    /// nil, los primeros `cuantos` de la lista. Un ajuste vacío no muestra ninguno.
    public static func elegir(todos: [String], preferidos: [String]?, cuantos: Int = cuantosPorOmision) -> [String] {
        guard let preferidos else { return Array(todos.prefix(max(0, cuantos))) }
        var salida: [String] = []
        for p in preferidos {
            let n = BusquedaApps.normalizar(p)
            guard let real = todos.first(where: { $0 == p }) ?? todos.first(where: { BusquedaApps.normalizar($0) == n }),
                  !salida.contains(real) else { continue }
            salida.append(real)
        }
        return salida
    }

    /// La primera línea con texto de lo que escribió el atajo en stderr (para la ayuda del mosaico); un texto fijo si no hay.
    public static func primeraLinea(_ error: String, porOmision: String = "El atajo falló") -> String {
        let linea = error.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
        return linea.map { String($0.prefix(160)) } ?? porOmision
    }
}
