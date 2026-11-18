import Foundation

/// El día laboral dibujado como una línea: todo en fracciones de 0 a 1 del ancho, para que la vista solo multiplique.
public struct LineaDelDia: Equatable, Sendable {
    public struct Tramo: Equatable, Sendable {
        public var inicio: Double
        public var ancho: Double
        public var fin: Double { inicio + ancho }
        public init(inicio: Double, ancho: Double) {
            self.inicio = inicio
            self.ancho = ancho
        }
    }

    public struct Marca: Equatable, Sendable {
        public var fraccion: Double
        /// La hora en doce horas, como se escribe en la línea: 8, 10, 12, 2, 4, 6.
        public var etiqueta: String
    }

    public var eventos: [Tramo]
    public var libre: Tramo?
    /// La marca roja de "ahora"; nil si ahora cae fuera del horario o el día no es hoy.
    public var ahora: Double?
    public var marcas: [Marca]

    /// Arma la línea de `dia` entre `inicioHora` y `finHora`. Los eventos que se encimen se funden en un solo bloque; lo
    /// que cae fuera del horario se recorta o se descarta; el hueco libre solo se dibuja si es de ese día.
    public static func armar(dia: Date, eventos: [Intervalo], libre: Intervalo?, ahora: Date, inicioHora: Int, finHora: Int,
                             cadaHoras: Int = 2, calendario: Calendar = .current) -> LineaDelDia {
        let desde = max(0, min(inicioHora, 23)), hasta = max(desde + 1, min(finHora, 24))
        let base = calendario.startOfDay(for: dia)
        func fecha(_ hora: Int) -> Date { calendario.date(byAdding: .hour, value: hora, to: base) ?? base }
        let abre = fecha(desde), cierra = fecha(hasta)
        let largo = cierra.timeIntervalSince(abre)
        guard largo > 0 else { return LineaDelDia(eventos: [], libre: nil, ahora: nil, marcas: []) }
        func tramo(_ i: Intervalo) -> Tramo? {
            let a = max(i.inicio, abre), b = min(i.fin, cierra)
            guard b > a else { return nil }
            return Tramo(inicio: a.timeIntervalSince(abre) / largo, ancho: b.timeIntervalSince(a) / largo)
        }
        let bloques = Huecos.unir(eventos).compactMap(tramo)
        let hueco = libre.flatMap { calendario.isDate($0.inicio, inSameDayAs: dia) ? tramo($0) : nil }
        var marcaAhora: Double?
        if calendario.isDate(ahora, inSameDayAs: dia), ahora >= abre, ahora <= cierra {
            marcaAhora = ahora.timeIntervalSince(abre) / largo
        }
        var marcas: [Marca] = []
        var h = desde
        while h <= hasta {
            let doce = h % 12 == 0 ? 12 : h % 12
            marcas.append(Marca(fraccion: Double(h - desde) / Double(hasta - desde), etiqueta: "\(doce)"))
            h += max(1, cadaHoras)
        }
        return LineaDelDia(eventos: bloques, libre: hueco, ahora: marcaAhora, marcas: marcas)
    }
}
