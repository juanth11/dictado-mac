import Foundation

// La sección Noticias del Centro (`python3 -m centro noticias --json`): el radar por vertical. Titular, fuente, cuándo, por qué te
// importa y el enlace (solo http o https; un enlace de otro tipo no se abre).

public struct NoticiaCentro: Equatable, Sendable, Identifiable {
    public var id: String
    public var vertical: String
    public var titulo: String
    public var fuente: String
    /// "9 oct" (lo que trae el radar).
    public var fecha: String
    /// ISO con zona si el radar la trae (el VPS actual aún no); da la hora.
    public var publicada: Date?
    public var porQue: String
    public var url: URL?

    public init(id: String, vertical: String, titulo: String, fuente: String = "", fecha: String = "", publicada: Date? = nil, porQue: String = "", url: URL? = nil) {
        self.id = id
        self.vertical = vertical
        self.titulo = titulo
        self.fuente = fuente
        self.fecha = fecha
        self.publicada = publicada
        self.porQue = porQue
        self.url = url
    }
}

public struct VerticalNoticias: Equatable, Sendable, Identifiable {
    public var vertical: String
    public var items: [NoticiaCentro]
    public var id: String { vertical }

    public init(vertical: String, items: [NoticiaCentro]) {
        self.vertical = vertical
        self.items = items
    }
}

public struct Noticias: Equatable, Sendable {
    public var disponible: Bool
    public var origen: String?
    public var generado: Date?
    public var diasSinActualizar: Int?
    public var verticales: [VerticalNoticias]
    public var motivo: String?

    public init(disponible: Bool = false, origen: String? = nil, generado: Date? = nil, diasSinActualizar: Int? = nil, verticales: [VerticalNoticias] = [], motivo: String? = nil) {
        self.disponible = disponible
        self.origen = origen
        self.generado = generado
        self.diasSinActualizar = diasSinActualizar
        self.verticales = verticales
        self.motivo = motivo
    }

    public var total: Int { verticales.reduce(0) { $0 + $1.items.count } }
}

public enum NoticiasCentro {
    public static func decodificar(_ datos: Data) -> Noticias? {
        guard let d = LecturaJSON.objeto(datos), let version = LecturaJSON.entero(d["version"]), version >= 1, d["verticales"] is [Any] else { return nil }
        let verticales: [VerticalNoticias] = (d["verticales"] as? [[String: Any]] ?? []).compactMap { v in
            guard let nombre = LecturaJSON.texto(v["vertical"]) else { return nil }
            let items: [NoticiaCentro] = (v["items"] as? [[String: Any]] ?? []).compactMap { x in
                guard let t = LecturaJSON.texto(x["titulo"]) else { return nil }
                return NoticiaCentro(id: LecturaJSON.texto(x["id"]) ?? t, vertical: nombre, titulo: t, fuente: LecturaJSON.texto(x["fuente"]) ?? "",
                                     fecha: LecturaJSON.texto(x["fecha"]) ?? "", publicada: LecturaJSON.fecha(x["publicada"]), porQue: LecturaJSON.texto(x["por_que"]) ?? "",
                                     url: LecturaJSON.texto(x["url"]).flatMap(enlaceSeguro))
            }
            return items.isEmpty ? nil : VerticalNoticias(vertical: nombre, items: items)
        }
        return Noticias(disponible: LecturaJSON.booleano(d["disponible"]) ?? !verticales.isEmpty, origen: LecturaJSON.texto(d["origen"]),
                        generado: LecturaJSON.fecha(d["generado"]), diasSinActualizar: LecturaJSON.entero(d["dias_sin_actualizar"]), verticales: verticales,
                        motivo: LecturaJSON.texto(d["motivo"]))
    }

    /// Solo web: una noticia nunca abre otra cosa.
    public static func enlaceSeguro(_ texto: String) -> URL? {
        guard let url = URL(string: texto), let e = url.scheme?.lowercased(), ["https", "http"].contains(e) else { return nil }
        return url
    }

    /// "9 oct · 14:05" si el radar trae la hora; si no, solo "9 oct".
    public static func cuando(_ n: NoticiaCentro, calendario: Calendar = .current) -> String {
        guard let p = n.publicada else { return n.fecha }
        return "\(TextoTiempo.diaCorto(p, calendario: calendario)) · \(TextoTiempo.hora(p, calendario: calendario))"
    }
}
