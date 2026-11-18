import AppKit
import DictadoKit
import Observation
import SwiftUI

// El clima, en un solo lugar: lo leen el lanzador (la frase del hueco), la pieza "clima" del Dock y, cuando se quiera, la isla.
// Fuente: Open-Meteo (sin clave). Solo viaja el nombre de una ciudad (para ubicarla, una sola vez) o unas coordenadas; nunca tu
// nombre, tus archivos ni ningún identificador.
//
// El lugar, sin permisos nuevos (nada de Localización):
//   defaults write app.dictado clima.lugar "Medellín"            (la ciudad; se ubica una vez y se recuerda)
//   defaults write app.dictado clima.coordenadas "6.25,-75.56"   (si se pone, manda sobre la búsqueda)
//   sin ninguno de los dos: la ciudad de la zona horaria del Mac (America/Bogota → Bogota).
//
// Se pide como mucho cada 30 minutos y solo mientras algo que lo muestra está a la vista (cada pieza avisa con `alMostrar` y
// `alOcultar`); fuera del hilo principal y con un tope de 8 segundos. Sin red o con una respuesta rota, la frase pasa a ser la
// fecha de hoy: nunca un error.

@MainActor @Observable
final class ClimaModelo {
    static let compartido = ClimaModelo()

    private(set) var actual: ClimaActual?
    private(set) var lugar: String = ""
    private(set) var ultimoExito: Date?

    @ObservationIgnored private let vivo: Bool
    @ObservationIgnored private var usuarios = 0
    @ObservationIgnored private var ultimoIntento: Date?
    @ObservationIgnored private var fallo = false
    @ObservationIgnored private var pidiendo = false
    @ObservationIgnored private var reloj: Timer?
    @ObservationIgnored private var tarea: Task<Void, Never>?
    @ObservationIgnored private let defaults: UserDefaults

    nonisolated static let claveLugar = "clima.lugar"
    nonisolated static let claveCoordenadas = "clima.coordenadas"
    /// "ciudad|latitud|longitud|nombre": la ciudad que se pidió y lo que respondió la geocodificación.
    nonisolated static let claveResuelto = "clima.resuelto"

    init(vivo: Bool = true, defaults: UserDefaults = .dictado) {
        self.vivo = vivo
        self.defaults = defaults
    }

    /// Algo que muestra el clima se puso a la vista: pide si toca y se queda al pendiente cada 30 minutos mientras siga a la vista.
    func alMostrar() {
        usuarios += 1
        guard vivo, usuarios == 1 else { return actualizarSiToca() }
        actualizarSiToca()
        reloj = Timer.scheduledTimer(withTimeInterval: PoliticaClima.intervalo, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.actualizarSiToca() }
        }
        reloj?.tolerance = 60
    }

    func alOcultar() {
        usuarios = max(0, usuarios - 1)
        guard usuarios == 0 else { return }
        reloj?.invalidate()
        reloj = nil
        tarea?.cancel()
        tarea = nil
        pidiendo = false
    }

    private func actualizarSiToca() {
        guard vivo, !pidiendo, PoliticaClima.debeActualizar(ultimoIntento: ultimoIntento, fallo: fallo, ahora: Date()) else { return }
        pidiendo = true
        ultimoIntento = Date()
        let lugarAjustado = defaults.string(forKey: Self.claveLugar)?.trimmingCharacters(in: .whitespaces) ?? ""
        let coordenadas = defaults.string(forKey: Self.claveCoordenadas).flatMap(ClimaPuro.coordenadas)
        let resuelto = defaults.string(forKey: Self.claveResuelto)
        let zona = TimeZone.current.identifier
        tarea = Task.detached(priority: .utility) {
            let r = await Self.consultar(lugarAjustado: lugarAjustado, coordenadas: coordenadas, resuelto: resuelto, zona: zona)
            await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled else { return }
                self.pidiendo = false
                guard let r else { self.fallo = true; return }
                self.fallo = false
                self.actual = r.clima
                self.lugar = r.nombre
                self.ultimoExito = Date()
                if let nuevo = r.resuelto { self.defaults.set(nuevo, forKey: Self.claveResuelto) }
            }
        }
    }

    private struct Resultado: Sendable {
        var clima: ClimaActual
        var nombre: String
        var resuelto: String?
    }

    /// Fuera del hilo principal: ubica la ciudad (una vez, o ya recordada) y pide el pronóstico.
    nonisolated private static func consultar(lugarAjustado: String, coordenadas: (latitud: Double, longitud: Double)?, resuelto: String?,
                                              zona: String) async -> Resultado? {
        let ciudad = lugarAjustado.isEmpty ? ClimaPuro.ciudad(zonaHoraria: zona) : lugarAjustado
        var la: Double, lo: Double, nombre: String
        var nuevoResuelto: String?
        if let c = coordenadas {
            (la, lo) = (c.latitud, c.longitud)
            nombre = ciudad ?? "tu zona"
        } else {
            guard let ciudad else { return nil }
            let partes = (resuelto ?? "").components(separatedBy: "|")
            if partes.count == 4, partes[0] == ciudad, let a = Double(partes[1]), let b = Double(partes[2]) {
                (la, lo, nombre) = (a, b, partes[3])
            } else {
                guard let url = ClimaPuro.urlGeocodificacion(ciudad: ciudad), let datos = await descargar(url),
                      let l = ClimaPuro.analizarGeocodificacion(datos) else { return nil }
                (la, lo, nombre) = (l.latitud, l.longitud, l.nombre)
                nuevoResuelto = [ciudad, String(l.latitud), String(l.longitud), l.nombre].joined(separator: "|")
            }
        }
        guard let url = ClimaPuro.urlPronostico(latitud: la, longitud: lo), let datos = await descargar(url),
              let clima = ClimaPuro.analizar(datos) else { return nil }
        return Resultado(clima: clima, nombre: nombre, resuelto: nuevoResuelto)
    }

    nonisolated private static func descargar(_ url: URL) async -> Data? {
        var peticion = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        peticion.httpMethod = "GET"
        guard let (datos, respuesta) = try? await URLSession.shared.data(for: peticion),
              (respuesta as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return datos
    }

    // MARK: Lo que se muestra

    /// Los datos vigentes (menos de 3 horas), o nil: de ahí en adelante se muestra la fecha.
    func vigente(ahora: Date = Date()) -> (clima: ClimaActual, lugar: String)? {
        guard let a = actual, !lugar.isEmpty, PoliticaClima.vigente(ultimoExito: ultimoExito, ahora: ahora) else { return nil }
        return (a, lugar)
    }

    /// La frase de dos tonos: el clima o, sin datos, la fecha de hoy.
    func frase(ahora: Date = Date()) -> [SegmentoFrase] {
        if let v = vigente(ahora: ahora) { return FraseClima.frase(v.clima, lugar: v.lugar) }
        return FraseClima.sinDatos(ahora)
    }

    /// El texto de una línea para VoiceOver y las ayudas.
    func texto(ahora: Date = Date()) -> String {
        if let v = vigente(ahora: ahora) { return FraseClima.unaLinea(v.clima, lugar: v.lugar) }
        return Frase.texto(FraseClima.sinDatos(ahora)).replacingOccurrences(of: "\n", with: " ")
    }

    /// Renders y pruebas: datos ya listos, sin red.
    func fijar(_ clima: ClimaActual?, lugar: String, ahora: Date = Date()) {
        actual = clima
        self.lugar = lugar
        ultimoExito = clima == nil ? nil : ahora
    }
}

// MARK: - El hueco del lanzador

/// La frase del clima del lanzador: directo sobre el fondo (sin vidrio), en dos tonos y con el ícono del estado, como la maqueta.
struct ClimaLanzador: View {
    let clima: ClimaModelo
    let ahora: Date
    @Environment(\.auroraTema) private var tema

    private func lineas(_ segmentos: [SegmentoFrase]) -> [[SegmentoFrase]] {
        var salida: [[SegmentoFrase]] = [[]]
        for s in segmentos {
            if s.texto == "\n" { salida.append([]) } else { salida[salida.count - 1].append(s) }
        }
        return salida.filter { !$0.isEmpty }
    }

    private func atribuido(_ linea: [SegmentoFrase]) -> AttributedString {
        var salida = AttributedString()
        for s in linea {
            var parte = AttributedString(s.texto)
            parte.foregroundColor = s.tono == .enlace ? tema.textoSuave : tema.textoPleno
            salida.append(parte)
        }
        return salida
    }

    var body: some View {
        let v = clima.vigente(ahora: ahora)
        let ls = lineas(clima.frase(ahora: ahora))
        let simbolo = v.map { ClimaPuro.simbolo(codigo: $0.clima.codigo, esDia: $0.clima.esDia) }
        VStack(alignment: .leading, spacing: 34 * (AuroraTipo.fraseInterlinea - 1.19)) {
            ForEach(Array(ls.enumerated()), id: \.offset) { i, linea in
                HStack(spacing: 7) {
                    if i == ls.count - 1, let simbolo {
                        Image(systemName: simbolo).symbolRenderingMode(.hierarchical).font(.system(size: 29, weight: .medium))
                            .foregroundStyle(tema.textoPleno)
                    }
                    Text(atribuido(linea))
                        .font(AuroraTipo.frase(34))
                        .tracking(34 * AuroraTipo.fraseInterletra)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .shadow(color: .black.opacity(tema.esOscuro ? 0.35 : 0), radius: 7, y: 2)
        .padding(.leading, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(clima.texto(ahora: ahora))
        .onAppear { clima.alMostrar() }
        .onDisappear { clima.alOcultar() }
    }
}
