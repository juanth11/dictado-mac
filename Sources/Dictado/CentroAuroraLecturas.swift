import AppKit
import DictadoKit
import Observation
import SwiftUI

// Las lecturas de las secciones nuevas del Centro (Consumo, Herramientas, Finanzas, Noticias y Automatizaciones). Cada una corre UN
// subcomando JSON del paquete `centro` (`python3 -m centro consumo --json`…), fuera del hilo principal y con tope de tiempo, como mucho
// una vez por su frecuencia, y solo mientras la sección está a la vista. La app solo lee: todo se calcula en el paquete y se suelta al cerrar.

@MainActor @Observable
final class LecturaCentro<Valor: Sendable> {
    /// nil = no se pudo leer (sin centro, el comando falló o no respondió).
    private(set) var valor: Valor?
    private(set) var leido: Date?
    private(set) var cargando = false
    /// Por qué no hay lectura ("no respondió en 45 s"): la sección lo dice en una línea.
    private(set) var fallo: String?

    @ObservationIgnored private let argumentos: [String]
    @ObservationIgnored private let limite: TimeInterval
    @ObservationIgnored private let frecuencia: TimeInterval
    @ObservationIgnored private let decodificar: @Sendable (Data) -> Valor?
    @ObservationIgnored private let vivo: Bool
    @ObservationIgnored private var ultimaPeticion: Date?

    init(argumentos: [String], limite: TimeInterval = 40, frecuencia: TimeInterval = 120, vivo: Bool = true, decodificar: @escaping @Sendable (Data) -> Valor?) {
        self.argumentos = argumentos
        self.limite = limite
        self.frecuencia = frecuencia
        self.vivo = vivo
        self.decodificar = decodificar
    }

    /// ¿Hay centro configurado para pedir?
    var disponible: Bool { vivo && TareasIsla.carpetaCentro != nil }

    func refrescar(forzar: Bool = false) {
        guard vivo, !cargando else { return }
        guard let carpeta = TareasIsla.carpetaCentro else {
            fallo = "El centro no está configurado en este Mac."
            return
        }
        guard forzar || TableroCentro.tocaPedir(ultima: ultimaPeticion, ahora: Date(), frecuencia: frecuencia) else { return }
        ultimaPeticion = Date()
        cargando = true
        let args = ["-m", "centro"] + argumentos
        let tope = limite
        let leer = decodificar
        Task.detached(priority: .userInitiated) {
            let r = CentroStore.correr(URL(fileURLWithPath: "/usr/bin/python3"), args, limite: tope, carpeta: carpeta)
            let v = r.error == nil ? leer(r.datos) : nil
            let motivo = r.error ?? (v == nil ? "El centro respondió algo que esta versión no entiende." : nil)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.cargando = false
                if let v {
                    self.valor = v
                    self.leido = Date()
                    self.fallo = nil
                } else {
                    // Se sigue mostrando lo último que se supo; solo se anota por qué falló.
                    self.fallo = motivo
                }
            }
        }
    }

    /// Para los renders y las pruebas: lo que se muestra, sin leer nada.
    func fijar(_ valor: Valor?, leido: Date = Date(), fallo: String? = nil) {
        self.valor = valor
        self.leido = valor == nil ? nil : leido
        self.fallo = fallo
    }

    func soltar() {
        valor = nil
        leido = nil
        fallo = nil
        ultimaPeticion = nil
    }
}

/// Las cinco lecturas nuevas, con sus argumentos y frecuencias.
@MainActor
final class LecturasCentro {
    let consumo: LecturaCentro<Consumo>
    let herramientas: LecturaCentro<Herramientas>
    let finanzas: LecturaCentro<Finanzas>
    let noticias: LecturaCentro<Noticias>
    let automatizaciones: LecturaCentro<Automatizaciones>

    init(vivo: Bool = true) {
        // El primer consumo indexa ~/.claude/projects (unos 10 s) y el VPS se lee por ssh: por eso el tope largo.
        consumo = LecturaCentro(argumentos: ["consumo", "--json", "--presupuesto", "30"], limite: 60, frecuencia: 120, vivo: vivo) { ConsumoCentro.decodificar($0) }
        herramientas = LecturaCentro(argumentos: ["herramientas", "--json", "--presupuesto", "30"], limite: 60, frecuencia: 300, vivo: vivo) { HerramientasCentro.decodificar($0) }
        finanzas = LecturaCentro(argumentos: ["finanzas", "--json"], limite: 20, frecuencia: 300, vivo: vivo) { FinanzasCentro.decodificar($0) }
        noticias = LecturaCentro(argumentos: ["noticias", "--json"], limite: 40, frecuencia: 600, vivo: vivo) { NoticiasCentro.decodificar($0) }
        automatizaciones = LecturaCentro(argumentos: ["automatizaciones", "--json"], limite: 40, frecuencia: 120, vivo: vivo) { AutomatizacionesCentro.decodificar($0) }
    }

    func leer(_ s: SeccionAurora) {
        switch s {
        case .consumo: consumo.refrescar()
        case .herramientas: herramientas.refrescar()
        case .finanzas: finanzas.refrescar()
        case .noticias: noticias.refrescar()
        case .automatizaciones: automatizaciones.refrescar()
        case .hoy, .tablero, .semana, .reuniones, .mac: break
        }
    }

    func soltar() {
        consumo.soltar()
        herramientas.soltar()
        finanzas.soltar()
        noticias.soltar()
        automatizaciones.soltar()
    }
}
