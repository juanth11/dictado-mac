import Foundation

public enum DireccionRejilla: Sendable { case arriba, abajo, izquierda, derecha }

/// La disposición del lanzador de Aurora: 10 columnas × 4 filas. Con widgets, cinco bloques de 2×2 ocupan los lados
/// (Fecha y Música a la izquierda, Clima junto a ellos, Agentes y Agenda a la derecha) y las apps llenan el resto, en
/// orden de lectura: columnas 5-8 de las filas 1-2 y columnas 3-8 de las filas 3-4 (20 apps por página). Sin widgets
/// (al buscar) las 40 celdas son de apps. Lo que no cabe pasa a la página siguiente; los widgets no se mueven.
public struct RejillaLanzador: Equatable, Sendable {
    public struct Celda: Equatable, Sendable {
        public var fila: Int
        public var columna: Int
        public init(fila: Int, columna: Int) {
            self.fila = fila
            self.columna = columna
        }
    }

    /// Un rectángulo de celdas (desde 0).
    public struct Bloque: Equatable, Sendable {
        public var columna: Int, fila: Int, ancho: Int, alto: Int
        public init(columna: Int, fila: Int, ancho: Int, alto: Int) {
            self.columna = columna
            self.fila = fila
            self.ancho = ancho
            self.alto = alto
        }
        func contiene(_ c: Celda) -> Bool {
            c.columna >= columna && c.columna < columna + ancho && c.fila >= fila && c.fila < fila + alto
        }
    }

    public static let columnas = 10
    public static let filas = 4
    public static let fecha = Bloque(columna: 0, fila: 0, ancho: 2, alto: 2)
    public static let musica = Bloque(columna: 0, fila: 2, ancho: 2, alto: 2)
    /// Reservado para la frase del clima, que va directo sobre el fondo.
    public static let clima = Bloque(columna: 2, fila: 0, ancho: 2, alto: 2)
    public static let agentes = Bloque(columna: 8, fila: 0, ancho: 2, alto: 2)
    public static let agenda = Bloque(columna: 8, fila: 2, ancho: 2, alto: 2)
    public static let bloquesWidgets = [fecha, musica, clima, agentes, agenda]

    public let total: Int
    public let conWidgets: Bool
    /// Las celdas que se llenan con apps en cada página, en orden.
    public let ranuras: [Celda]

    public init(total: Int, conWidgets: Bool) {
        self.total = max(total, 0)
        self.conWidgets = conWidgets
        var lista: [Celda] = []
        for fila in 0..<Self.filas {
            for columna in 0..<Self.columnas {
                let c = Celda(fila: fila, columna: columna)
                if conWidgets, Self.bloquesWidgets.contains(where: { $0.contiene(c) }) { continue }
                lista.append(c)
            }
        }
        ranuras = lista
    }

    public var porPagina: Int { ranuras.count }
    public var paginas: Int { max(1, (total + porPagina - 1) / porPagina) }

    public func pagina(de indice: Int) -> Int { max(indice, 0) / porPagina }

    /// Los índices de las apps de una página.
    public func rango(pagina: Int) -> Range<Int> {
        let desde = min(max(pagina, 0) * porPagina, total)
        return desde..<min(desde + porPagina, total)
    }

    public func celda(de indice: Int) -> Celda { ranuras[max(indice, 0) % porPagina] }

    /// A dónde va la selección. Izquierda y derecha siguen el orden (y cruzan de página); arriba y abajo buscan, en la fila
    /// vecina de la misma página, la celda de la columna más cercana. En el borde se queda donde está.
    public func mover(desde actual: Int, _ direccion: DireccionRejilla) -> Int {
        guard total > 0 else { return 0 }
        let i = min(max(actual, 0), total - 1)
        switch direccion {
        case .izquierda: return max(0, i - 1)
        case .derecha: return min(total - 1, i + 1)
        case .arriba, .abajo:
            let c = celda(de: i)
            let fila = c.fila + (direccion == .abajo ? 1 : -1)
            let candidatas = rango(pagina: pagina(de: i)).filter { celda(de: $0).fila == fila }
            return candidatas.min { abs(celda(de: $0).columna - c.columna) < abs(celda(de: $1).columna - c.columna) } ?? i
        }
    }
}
