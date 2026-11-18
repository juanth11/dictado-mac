import Foundation

/// El clima de ahora y el de hoy, ya leído (números enteros, como se muestran).
public struct ClimaActual: Equatable, Sendable {
    public var temperatura: Int
    public var sensacion: Int
    /// Código del tiempo (WMO), el que usa Open-Meteo.
    public var codigo: Int
    public var esDia: Bool
    public var maxima: Int?
    public var minima: Int?

    public init(temperatura: Int, sensacion: Int, codigo: Int, esDia: Bool, maxima: Int? = nil, minima: Int? = nil) {
        self.temperatura = temperatura
        self.sensacion = sensacion
        self.codigo = codigo
        self.esDia = esDia
        self.maxima = maxima
        self.minima = minima
    }
}

/// Un lugar resuelto por el servicio de geocodificación.
public struct LugarClima: Equatable, Sendable {
    public var nombre: String
    public var latitud: Double
    public var longitud: Double

    public init(nombre: String, latitud: Double, longitud: Double) {
        self.nombre = nombre
        self.latitud = latitud
        self.longitud = longitud
    }
}

/// El clima, sin red ni ventanas: las direcciones, la lectura de las respuestas de Open-Meteo, la tabla de códigos y las frases.
/// De aquí solo sale el nombre de una ciudad o unas coordenadas; nada más viaja.
public enum ClimaPuro {
    // MARK: Direcciones

    /// El pronóstico de Open-Meteo (sin clave): ahora, y máxima y mínima de hoy. La hora local sale de la zona del lugar.
    public static func urlPronostico(latitud: Double, longitud: Double) -> URL? {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        c?.queryItems = [
            URLQueryItem(name: "latitude", value: numero(latitud)),
            URLQueryItem(name: "longitude", value: numero(longitud)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        return c?.url
    }

    /// La búsqueda de una ciudad por nombre (solo el primer resultado, en español).
    public static func urlGeocodificacion(ciudad: String) -> URL? {
        let limpia = ciudad.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpia.isEmpty else { return nil }
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        c?.queryItems = [
            URLQueryItem(name: "name", value: limpia),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "language", value: "es"),
            URLQueryItem(name: "format", value: "json"),
        ]
        return c?.url
    }

    private static func numero(_ v: Double) -> String { String(format: "%.4f", v) }

    // MARK: El lugar

    /// La ciudad de un identificador de zona horaria: "America/Bogota" → "Bogota"; "America/Argentina/Buenos_Aires" → "Buenos Aires".
    /// nil para "UTC", "GMT" y cosas sin ciudad.
    public static func ciudad(zonaHoraria id: String) -> String? {
        guard id.contains("/"), let ultima = id.split(separator: "/").last else { return nil }
        let nombre = ultima.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
        return nombre.isEmpty || ["UTC", "GMT"].contains(nombre) ? nil : nombre
    }

    /// "4.61,-74.08" (o "4.61, -74.08") → (4.61, -74.08); nil si no son dos números en rango.
    public static func coordenadas(_ texto: String) -> (latitud: Double, longitud: Double)? {
        let partes = texto.split(whereSeparator: { $0 == "," || $0 == ";" }).map { $0.trimmingCharacters(in: .whitespaces) }
        guard partes.count == 2, let la = Double(partes[0]), let lo = Double(partes[1]), (-90...90).contains(la), (-180...180).contains(lo) else { return nil }
        return (la, lo)
    }

    public static func texto(latitud: Double, longitud: Double) -> String { numero(latitud) + "," + numero(longitud) }

    // MARK: Respuestas

    /// Lee la respuesta del pronóstico. nil si falta la temperatura o el código (una respuesta rota nunca muestra números inventados).
    public static func analizar(_ datos: Data) -> ClimaActual? {
        guard let raiz = (try? JSONSerialization.jsonObject(with: datos)) as? [String: Any],
              let ahora = raiz["current"] as? [String: Any],
              let t = (ahora["temperature_2m"] as? NSNumber)?.doubleValue,
              let codigo = (ahora["weather_code"] as? NSNumber)?.intValue else { return nil }
        let sensacion = (ahora["apparent_temperature"] as? NSNumber)?.doubleValue ?? t
        let dia = (ahora["is_day"] as? NSNumber)?.intValue ?? 1
        let diario = raiz["daily"] as? [String: Any]
        func primero(_ clave: String) -> Int? { ((diario?[clave] as? [Any])?.first as? NSNumber).map { entero($0.doubleValue) } }
        return ClimaActual(temperatura: entero(t), sensacion: entero(sensacion), codigo: codigo, esDia: dia != 0,
                           maxima: primero("temperature_2m_max"), minima: primero("temperature_2m_min"))
    }

    /// El primer resultado de la geocodificación (nombre, latitud, longitud). nil si no hay resultados.
    public static func analizarGeocodificacion(_ datos: Data) -> LugarClima? {
        guard let raiz = (try? JSONSerialization.jsonObject(with: datos)) as? [String: Any],
              let primero = (raiz["results"] as? [[String: Any]])?.first,
              let nombre = primero["name"] as? String, !nombre.isEmpty,
              let la = (primero["latitude"] as? NSNumber)?.doubleValue, let lo = (primero["longitude"] as? NSNumber)?.doubleValue,
              (-90...90).contains(la), (-180...180).contains(lo) else { return nil }
        return LugarClima(nombre: nombre, latitud: la, longitud: lo)
    }

    private static func entero(_ v: Double) -> Int {
        let r = Int(v.rounded())
        return r
    }

    // MARK: Códigos del tiempo

    /// La descripción en español de un código WMO.
    public static func descripcion(codigo: Int) -> String {
        switch codigo {
        case 0: return "Despejado"
        case 1: return "Mayormente despejado"
        case 2: return "Parcialmente nublado"
        case 3: return "Nublado"
        case 45, 48: return "Niebla"
        case 51: return "Llovizna ligera"
        case 53: return "Llovizna"
        case 55: return "Llovizna densa"
        case 56, 57: return "Llovizna helada"
        case 61: return "Lluvia ligera"
        case 63: return "Lluvia"
        case 65: return "Lluvia fuerte"
        case 66, 67: return "Lluvia helada"
        case 71: return "Nevada ligera"
        case 73: return "Nevada"
        case 75: return "Nevada fuerte"
        case 77: return "Granizo fino"
        case 80: return "Chubascos ligeros"
        case 81: return "Chubascos"
        case 82: return "Chubascos violentos"
        case 85, 86: return "Chubascos de nieve"
        case 95: return "Tormenta"
        case 96, 99: return "Tormenta con granizo"
        default: return "Variable"
        }
    }

    /// El símbolo de SF Symbols que acompaña al código (de día o de noche).
    public static func simbolo(codigo: Int, esDia: Bool) -> String {
        switch codigo {
        case 0: return esDia ? "sun.max" : "moon.stars"
        case 1, 2: return esDia ? "cloud.sun" : "cloud.moon"
        case 3: return "cloud"
        case 45, 48: return "cloud.fog"
        case 51, 53, 55, 56, 57: return "cloud.drizzle"
        case 61, 63, 66, 67: return "cloud.rain"
        case 65, 82: return "cloud.heavyrain"
        case 80, 81: return esDia ? "cloud.sun.rain" : "cloud.moon.rain"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow"
        case 95, 96, 99: return "cloud.bolt.rain"
        default: return "cloud"
        }
    }
}

/// Las frases del clima: segmentos de dos tonos (el dato pleno, el enlace atenuado) con saltos de línea, como la maqueta
/// ("18° ahora en / Bogotá / se siente 17° / Despejado"). Se dibujan con `FraseAurora`.
public enum FraseClima {
    /// Con datos: ahora, el lugar, cómo se siente (solo si difiere) y el estado.
    public static func frase(_ c: ClimaActual, lugar: String) -> [SegmentoFrase] {
        var p: [(String, TonoFrase)] = [("\(c.temperatura)°", .dato), ("ahora en", .enlace), ("\n", .enlace), (lugar, .dato), ("\n", .enlace)]
        if c.sensacion != c.temperatura { p += [("se siente", .enlace), ("\(c.sensacion)°", .dato), ("\n", .enlace)] }
        p.append((ClimaPuro.descripcion(codigo: c.codigo), .dato))
        return Frase.armar(p)
    }

    /// La misma frase en una línea: "18° ahora en Bogotá · se siente 17° · Despejado".
    public static func unaLinea(_ c: ClimaActual, lugar: String) -> String {
        var partes = ["\(c.temperatura)° ahora en \(lugar)"]
        if c.sensacion != c.temperatura { partes.append("se siente \(c.sensacion)°") }
        partes.append(ClimaPuro.descripcion(codigo: c.codigo))
        return partes.joined(separator: " · ")
    }

    private static let dias = ["domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado"]
    private static let meses = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"]

    /// Sin datos (sin red, sin lugar, una respuesta rota): la fecha de hoy, en el mismo formato. Nunca un error.
    public static func sinDatos(_ fecha: Date, calendario: Calendar = .current) -> [SegmentoFrase] {
        let c = calendario.dateComponents([.weekday, .day, .month], from: fecha)
        let dia = dias[((c.weekday ?? 1) - 1) % 7], mes = meses[((c.month ?? 1) - 1) % 12]
        return Frase.armar([("Hoy es", .enlace), ("\n", .enlace), (dia, .dato), ("\n", .enlace), ("\(c.day ?? 1) de \(mes)", .enlace)])
    }
}

/// Cuándo se vuelve a pedir el clima. Como mucho cada 30 minutos mientras se ve; si la última vez falló, se reintenta a los 10.
public enum PoliticaClima {
    public static let intervalo: TimeInterval = 30 * 60
    public static let reintento: TimeInterval = 10 * 60
    /// Un dato más viejo que esto ya no se muestra (se pasa a la fecha).
    public static let vigencia: TimeInterval = 3 * 3600

    public static func debeActualizar(ultimoIntento: Date?, fallo: Bool, ahora: Date) -> Bool {
        guard let u = ultimoIntento else { return true }
        let espera = fallo ? reintento : intervalo
        return ahora.timeIntervalSince(u) >= espera || ahora < u
    }

    public static func vigente(ultimoExito: Date?, ahora: Date) -> Bool {
        guard let u = ultimoExito else { return false }
        return ahora.timeIntervalSince(u) <= vigencia
    }
}
