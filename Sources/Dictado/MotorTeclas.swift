import AVFoundation
import DictadoKit
import os

private let log = Logger(subsystem: "app.dictado", category: "teclas")

/// Reproduce los sonidos de las teclas con AVAudioEngine, con la menor latencia posible:
///  - los buffers (cada sonido, en varias alturas de tono) se arman de antemano al elegir el perfil;
///  - hay un grupo fijo de reproductores que se turnan (varias teclas a la vez no se cortan entre sí);
///  - el motor queda andando mientras la función esté encendida, y parado al apagarla;
///  - al pulsar solo se elige un buffer, se pone el paneo y se agenda: no se crea nada.
/// Las funciones públicas se pueden llamar desde cualquier hilo.
final class MotorTeclas: @unchecked Sendable {
    struct Ajustes {
        var volumen: Float = 0.4
        var alSoltar = true
        /// 0 (sin variación) a 1 (todo el rango de ± `variacionMaxima`).
        var variacion: Float = 0.5
        var espacial = true
    }

    /// El tono varía hasta ±6 % en los perfiles sintetizados (9 alturas precalculadas) y solo ±2 % con tus grabaciones (3 alturas):
    /// un sonido real ya cambia de una pulsación a otra, y más tono lo vuelve de juguete.
    static let variacionMaxima = 0.06
    static let variacionMaximaGrabada = 0.02
    private static let alturas = 9
    private static let alturasGrabadas = 3
    private static let reproductores = 10

    /// Cada familia es una lista de sonidos y, de cada uno, sus versiones en distinta altura.
    private typealias Familia = [[AVAudioPCMBuffer]]

    private struct Juego {
        /// Sintetizado: solo `.normal` y `.espacio` (la clase pesada). Grabado: una por clase; la que falte cae en `.normal`.
        var abajo: [ClaseTecla: Familia] = [:]
        var arriba: [ClaseTecla: Familia] = [:]
        var grabado = false
    }

    private let motor = AVAudioEngine()
    private let formato = AVAudioFormat(standardFormatWithSampleRate: SintesisTeclas.tasa, channels: 1)!
    private var jugadores: [AVAudioPlayerNode] = []
    private var turno = 0
    private var juego = Juego()
    private var ajustes = Ajustes()
    private let cerrojo = NSLock()
    private var armado = false
    private(set) var sonando = false
    /// El último sonido que tocó cada familia (clase × abajo/arriba): nunca el mismo dos veces seguidas. Solo se toca desde la cola de audio.
    private var ultimos = [Int](repeating: -1, count: ClaseTecla.allCases.count * 2)
    /// Cola de audio: todo lo que toca el motor pasa por aquí, lejos del hilo principal y del del tap de teclado.
    let cola = DispatchQueue(label: "app.dictado.teclas.audio", qos: .userInteractive)
    private var observadorConfiguracion: NSObjectProtocol?
    /// Se llama (en la cola de audio) si el motor se detiene por un cambio de dispositivo y no logra volver.
    var alFallar: (@Sendable () -> Void)?

    func configurar(_ a: Ajustes) {
        cerrojo.withLock { ajustes = a }
        motor.mainMixerNode.outputVolume = min(max(a.volumen, 0), 1)
    }

    private func buffer(_ x: [Float]) -> AVAudioPCMBuffer? {
        guard let b = AVAudioPCMBuffer(pcmFormat: formato, frameCapacity: AVAudioFrameCount(x.count)),
              let canal = b.floatChannelData?[0] else { return nil }
        x.withUnsafeBufferPointer { canal.update(from: $0.baseAddress!, count: x.count) }
        b.frameLength = AVAudioFrameCount(x.count)
        return b
    }

    /// Arma los buffers del perfil (unos 50 ms de cálculo; se llama fuera del hilo principal).
    func preparar(_ perfil: PerfilTeclas) {
        let razones = SintesisTeclas.razones(maximo: Self.variacionMaxima, pasos: Self.alturas)
        func familia(abajo: Bool, grande: Bool) -> Familia {
            let base = SintesisTeclas.generar(perfil, abajo: abajo, grande: grande)
            return [razones.compactMap { buffer(SintesisTeclas.conTono(base, razon: $0)) }]
        }
        let nuevo = Juego(abajo: [.normal: familia(abajo: true, grande: false), .espacio: familia(abajo: true, grande: true)],
                          arriba: [.normal: familia(abajo: false, grande: false), .espacio: familia(abajo: false, grande: true)])
        cerrojo.withLock { juego = nuevo }
    }

    /// Arma los buffers de "Mi teclado": cada sonido grabado en tres alturas (±2 %). Se llama fuera del hilo principal.
    func preparar(grabado: JuegoTeclado) {
        let razones = SintesisTeclas.razones(maximo: Self.variacionMaximaGrabada, pasos: Self.alturasGrabadas)
        func familia(_ sonidos: [[Float]]) -> Familia {
            sonidos.map { base in razones.compactMap { buffer(SintesisTeclas.conTono(base, razon: $0)) } }.filter { !$0.isEmpty }
        }
        var nuevo = Juego(grabado: true)
        for (clase, par) in grabado.clases {
            let a = familia(par.abajo), u = familia(par.arriba)
            if !a.isEmpty { nuevo.abajo[clase] = a }
            if !u.isEmpty { nuevo.arriba[clase] = u }
        }
        cerrojo.withLock { juego = nuevo }
    }

    /// Enciende el motor y deja los reproductores listos. false si no hay dispositivo de salida o falla el arranque.
    func arrancar() -> Bool {
        cola.sync {
            guard !sonando else { return true }
            if !armado {
                for _ in 0..<Self.reproductores {
                    let j = AVAudioPlayerNode()
                    motor.attach(j)
                    motor.connect(j, to: motor.mainMixerNode, format: formato)
                    jugadores.append(j)
                }
                armado = true
            }
            observadorConfiguracion = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: motor, queue: nil) { [weak self] _ in
                self?.cola.async { self?.reiniciarTrasCambio() }
            }
            return encender()
        }
    }

    func parar() {
        cola.sync {
            if let o = observadorConfiguracion { NotificationCenter.default.removeObserver(o) }
            observadorConfiguracion = nil
            jugadores.forEach { $0.stop() }
            motor.stop()
            sonando = false
        }
    }

    private func encender() -> Bool {
        motor.prepare()
        do {
            try motor.start()
        } catch {
            log.error("no pude arrancar el audio: \(error.localizedDescription, privacy: .public)")
            sonando = false
            return false
        }
        jugadores.forEach { $0.play() }
        sonando = true
        return true
    }

    /// Cambió el dispositivo de salida (auriculares, AirPods…): el motor se detiene solo y hay que volver a arrancarlo.
    private func reiniciarTrasCambio() {
        guard sonando else { return }
        motor.stop()
        if !encender() { alFallar?() }
    }

    /// Un sonido de tecla. Solo recibe el código de tecla y si bajó o subió; no sabe qué carácter es.
    /// Llamar desde la cola de audio (`cola.async`). Elige un sonido al azar (nunca el mismo dos veces seguidas), le pone el
    /// paneo y lo agenda: no se crea ni se calcula nada al pulsar.
    func sonar(codigo: Int, abajo: Bool) {
        let (a, j): (Ajustes, Juego) = cerrojo.withLock { (ajustes, juego) }
        guard sonando, abajo || a.alSoltar else { return }
        let clase: ClaseTecla = j.grabado ? MapaTeclas.clase(codigo: codigo) : (MapaTeclas.esGrande(codigo: codigo) ? .espacio : .normal)
        let todas = abajo ? j.abajo : j.arriba
        guard let familia = todas[clase] ?? todas[.normal], !familia.isEmpty else { return }
        let clave = (todas[clase] != nil ? clase : .normal).indiceFamilia * 2 + (abajo ? 0 : 1)
        var m = 0
        if familia.count > 1 {
            repeat { m = Int.random(in: 0..<familia.count) } while m == ultimos[clave]
        }
        ultimos[clave] = m
        let alturas = familia[m]
        let medio = (alturas.count - 1) / 2
        let salto = Int((a.variacion * Float(medio)).rounded())
        let indice = salto == 0 ? medio : medio + Int.random(in: -salto...salto)
        let jugador = jugadores[turno]
        turno = (turno + 1) % jugadores.count
        jugador.pan = a.espacial ? Float(MapaTeclas.paneo(codigo: codigo)) : 0
        jugador.scheduleBuffer(alturas[indice], at: nil, options: .interrupts, completionHandler: nil)
    }
}

private extension ClaseTecla {
    var indiceFamilia: Int { ClaseTecla.allCases.firstIndex(of: self) ?? 0 }
}
