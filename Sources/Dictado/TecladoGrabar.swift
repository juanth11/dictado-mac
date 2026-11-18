import AppKit
import ApplicationServices
import AVFoundation
import DictadoKit
import Observation
import os
import SwiftUI

private let log = Logger(subsystem: "app.dictado", category: "teclas")

// "Grabar mi teclado…": una sesión corta y guiada que oye tu teclado con el micrófono y se queda solo con el sonido de cada
// tecla. Se empieza únicamente desde el menú de Teclas. Dura unos 50 segundos: 20 de escribir con normalidad y luego espacio,
// intro y retroceso, cinco veces cada uno.
//
// Qué se guarda: los recortes de cada sonido, en ~/Library/Application Support/Dictado/teclas/mi-teclado/ (un WAV por sonido).
// Qué no: la grabación (vive en memoria y se descarta al terminar), ni qué tecla fue cada una (solo si bajó o subió y su
// clase: normal, espacio, intro o retroceso). Usa el permiso de Micrófono que Dictado ya tiene (no pide uno nuevo: si falta,
// lo dice y se detiene) y la Accesibilidad de siempre para oír las teclas. Mientras graba, las teclas con sonido callan para
// que el micrófono no oiga la síntesis.

/// Graba el micrófono en memoria y anota cuándo bajó o subió cada tecla. Todo termina en `terminar()`.
final class CaptorTeclado: @unchecked Sendable {
    private let motor = AVAudioEngine()
    private let candado = NSLock()
    private var audio: [Float] = []
    private var eventos: [EventoTecla] = []
    private var t0 = 0.0
    private var tasa = SintesisTeclas.tasa
    private let tap = TapTeclas()
    /// Cada tecla que baja (su clase), en el hilo del tap.
    var alBajar: (@Sendable (ClaseTecla) -> Void)?

    @MainActor
    func empezar() throws {
        let entrada = motor.inputNode
        let formato = entrada.outputFormat(forBus: 0)
        guard formato.channelCount > 0, formato.sampleRate > 0 else { throw DictadoError.sinMicrofono }
        tasa = formato.sampleRate
        audio.reserveCapacity(Int(tasa * 60))
        entrada.installTap(onBus: 0, bufferSize: 4096, format: formato) { [weak self] buffer, _ in
            guard let self, let canal = buffer.floatChannelData?[0] else { return }
            let n = Int(buffer.frameLength)
            self.candado.withLock { self.audio.append(contentsOf: UnsafeBufferPointer(start: canal, count: n)) }
        }
        motor.prepare()
        t0 = ProcessInfo.processInfo.systemUptime
        try motor.start()
        let ok = tap.iniciar { [weak self] codigo, abajo, repeticion in
            guard let self, !repeticion, !MapaTeclas.silenciosa(codigo: codigo) else { return }
            let clase = MapaTeclas.clase(codigo: codigo)
            let t = ProcessInfo.processInfo.systemUptime - self.t0
            self.candado.withLock { self.eventos.append(EventoTecla(t: t, abajo: abajo, clase: clase)) }
            if abajo { self.alBajar?(clase) }
        }
        if !ok {
            motor.inputNode.removeTap(onBus: 0)
            motor.stop()
            throw DictadoError.sinMicrofono
        }
    }

    /// Para todo y entrega lo grabado (a la tasa de la entrada).
    @MainActor
    func terminar() -> (audio: [Float], tasa: Double, eventos: [EventoTecla]) {
        tap.detener()
        motor.inputNode.removeTap(onBus: 0)
        motor.stop()
        return candado.withLock {
            let r = (audio, tasa, eventos)
            audio = []
            eventos = []
            return r
        }
    }
}

/// Reanuda una espera una sola vez (por las teclas o por el tiempo, lo que llegue primero).
private final class UnaVez: @unchecked Sendable {
    private let candado = NSLock()
    private var k: CheckedContinuation<Void, Never>?
    init(_ k: CheckedContinuation<Void, Never>) { self.k = k }
    func seguir() {
        let c = candado.withLock { () -> CheckedContinuation<Void, Never>? in
            defer { k = nil }
            return k
        }
        c?.resume()
    }
}

@MainActor @Observable
final class SesionTeclado {
    enum Fase: Equatable {
        case inicio
        case cuenta(Int)
        case libre(restante: Int)
        case guiada(ClaseTecla, hechas: Int)
        case procesando
        case listo(String)
        case fallo(String)
    }

    static let segundosLibres = 20
    static let pulsacionesGuiadas = 5
    static let esperaGuiada = 12.0
    static let guiadas: [ClaseTecla] = [.espacio, .intro, .retroceso]

    var fase = Fase.inicio
    /// Cuántas teclas se han oído (solo para mostrar que el sistema oye).
    var teclasOidas = 0
    /// Terminó bien y "Mi teclado" quedó como sonido.
    var guardado = false
    @ObservationIgnored private var captor: CaptorTeclado?
    @ObservationIgnored private var tarea: Task<Void, Never>?
    @ObservationIgnored private var espera: (clase: ClaseTecla, seguir: () -> Void)?
    @ObservationIgnored var alGuardar: (() -> Void)?
    @ObservationIgnored var alEmpezar: (() -> Void)?
    @ObservationIgnored var alAcabar: (() -> Void)?

    init(fase: Fase = .inicio, teclas: Int = 0) {
        self.fase = fase
        teclasOidas = teclas
    }

    var activa: Bool {
        switch fase {
        case .cuenta, .libre, .guiada: return true
        default: return false
        }
    }

    // MARK: Empezar

    func empezar() {
        guard !activa, fase != .procesando else { return }
        // Sin permiso de micrófono no se pide nada: se dice y se detiene.
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            fase = .fallo("Falta el permiso de Micrófono para Dictado. Actívalo en Ajustes del Sistema → Privacidad y seguridad → Micrófono y vuelve a abrir esta ventana.")
            return
        }
        guard AXIsProcessTrusted() else {
            fase = .fallo("Falta la Accesibilidad para oír cuándo pulsas cada tecla. Actívala en Ajustes del Sistema → Privacidad y seguridad → Accesibilidad.")
            return
        }
        teclasOidas = 0
        guardado = false
        alEmpezar?()
        tarea = Task { await correr() }
    }

    private func correr() async {
        for n in stride(from: 3, to: 0, by: -1) {
            fase = .cuenta(n)
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { return }
        }
        let c = CaptorTeclado()
        c.alBajar = { [weak self] clase in DispatchQueue.main.async { MainActor.assumeIsolated { self?.oyo(clase) } } }
        do { try c.empezar() } catch {
            log.error("no pude grabar el teclado: \(error.localizedDescription, privacy: .public)")
            alAcabar?()
            fase = .fallo("No pude abrir el micrófono. Revisa que haya una entrada de sonido disponible.")
            return
        }
        captor = c
        for s in stride(from: Self.segundosLibres, to: 0, by: -1) {
            fase = .libre(restante: s)
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { return }
        }
        for clase in Self.guiadas {
            fase = .guiada(clase, hechas: 0)
            await withCheckedContinuation { (k: CheckedContinuation<Void, Never>) in
                let una = UnaVez(k)
                espera = (clase, { una.seguir() })
                Task {
                    try? await Task.sleep(for: .seconds(Self.esperaGuiada))
                    una.seguir()
                }
            }
            espera = nil
            if Task.isCancelled { return }
        }
        await terminar()
    }

    /// Una tecla bajó (en el hilo principal). Cuenta para la fase guiada si es de su clase.
    private func oyo(_ clase: ClaseTecla) {
        guard activa else { return }
        teclasOidas += 1
        if case .guiada(let c, let hechas) = fase, c == clase {
            fase = .guiada(c, hechas: hechas + 1)
            if hechas + 1 >= Self.pulsacionesGuiadas { espera?.seguir() }
        }
    }

    private func terminar() async {
        guard let c = captor else { return }
        captor = nil
        let r = c.terminar()
        alAcabar?()
        fase = .procesando
        let resultado: (String, Bool) = await Task.detached(priority: .userInitiated) {
            let x = abs(r.tasa - SintesisTeclas.tasa) < 1 ? r.audio : SintesisTeclas.conTono(r.audio, razon: r.tasa / SintesisTeclas.tasa)
            let (juego, informe) = CapturaTeclado.procesar(x, eventos: r.eventos)
            let ok = informe.suficiente()
            if ok {
                do { try AlmacenTeclado.guardar(juego, en: AlmacenTeclado.carpetaPorOmision()) } catch {
                    return ("No pude guardar los sonidos: \(error.localizedDescription)", false)
                }
            }
            return (informe.mensaje(), ok)
        }.value
        if resultado.1 {
            guardado = true
            alGuardar?()
            fase = .listo(resultado.0 + " Ya suena tu teclado.")
        } else {
            fase = .fallo(resultado.0)
        }
    }

    /// Cierra sin guardar nada: lo grabado se descarta.
    func cancelar() {
        tarea?.cancel()
        tarea = nil
        espera?.seguir()
        espera = nil
        if let c = captor {
            _ = c.terminar()
            captor = nil
            alAcabar?()
        }
        if fase != .procesando { fase = .inicio }
    }
}

// MARK: - La ventana

@MainActor
final class GrabarTeclado {
    static let shared = GrabarTeclado()
    /// Lo conecta `Teclas`: calla las teclas con sonido mientras se graba y recarga el sonido al guardar.
    var silenciar: ((Bool) -> Void)?
    var alGuardar: (() -> Void)?

    private var panel: PanelClave?
    private var sesion = SesionTeclado()

    func abrir() {
        if let p = panel, p.isVisible {
            p.makeKeyAndOrderFront(nil)
            return
        }
        sesion = SesionTeclado()
        sesion.alEmpezar = { [weak self] in self?.silenciar?(true) }
        sesion.alAcabar = { [weak self] in self?.silenciar?(false) }
        sesion.alGuardar = { [weak self] in self?.alGuardar?() }
        let p = PanelClave(contentRect: NSRect(x: 0, y: 0, width: VistaGrabarTeclado.ancho, height: VistaGrabarTeclado.alto),
                           styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: true)
        p.isFloatingPanel = true
        p.level = .floating
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.contentView = NSHostingView(rootView: VistaGrabarTeclado(sesion: sesion, cerrar: { [weak self] in self?.cerrar() }))
        if let z = NSScreen.main?.visibleFrame {
            p.setFrameOrigin(NSPoint(x: z.midX - VistaGrabarTeclado.ancho / 2, y: z.midY - VistaGrabarTeclado.alto / 2 + z.height * 0.08))
        }
        panel = p
        p.makeKeyAndOrderFront(nil)
    }

    func cerrar() {
        sesion.cancelar()
        silenciar?(false)
        panel?.orderOut(nil)
        panel = nil
    }
}

// MARK: - La vista

struct VistaGrabarTeclado: View {
    static let ancho: CGFloat = 470
    static let alto: CGFloat = 318

    let sesion: SesionTeclado
    var cerrar: () -> Void = {}
    var simulado = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Insignia(icono: .simbolo("keyboard"), tono: .azul, lado: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Grabar mi teclado").font(.system(size: 15, weight: .semibold)).foregroundStyle(Halo.texto)
                    Rotulo(rotulo, color: Halo.texto3)
                }
                Spacer(minLength: 0)
                if !sesion.activa { BotonCirculo(simbolo: "xmark", lado: 28, ayuda: "Cerrar") { cerrar() } }
            }
            Spacer(minLength: 10)
            contenido
            Spacer(minLength: 10)
            pie
        }
        .padding(22)
        .frame(width: Self.ancho, height: Self.alto)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .modifier(PanelVidrio(radio: 28, simulado: simulado))
        .animation(Halo.cambio, value: sesion.fase)
    }

    private var rotulo: String {
        switch sesion.fase {
        case .inicio: return "Unos 50 segundos"
        case .cuenta: return "Prepárate"
        case .libre, .guiada: return "Grabando"
        case .procesando: return "Cortando los sonidos"
        case .listo: return "Listo"
        case .fallo: return "No se pudo"
        }
    }

    @ViewBuilder private var contenido: some View {
        switch sesion.fase {
        case .inicio:
            VStack(alignment: .leading, spacing: 9) {
                Text("Dictado oye tu teclado un momento y se queda solo con el sonido de cada tecla, para que suene como el tuyo.")
                    .font(.system(size: 12.5)).foregroundStyle(Halo.texto2).fixedSize(horizontal: false, vertical: true)
                paso("1", "20 segundos escribiendo con normalidad")
                paso("2", "Espacio, Intro y Retroceso, cinco veces cada uno")
                Text("El audio no sale del Mac ni se guarda: solo los recortes. Pon silencio alrededor y sin música.")
                    .font(Halo.detalle).foregroundStyle(Halo.texto3).fixedSize(horizontal: false, vertical: true)
            }
        case .cuenta(let n):
            HStack(spacing: 16) {
                NumeroPuntos(texto: "\(n)", punto: 5, paso: 7)
                Text("Empieza a escribir cuando llegue a cero.").font(.system(size: 12.5)).foregroundStyle(Halo.texto2)
            }
        case .libre(let s):
            VStack(alignment: .leading, spacing: 10) {
                Text("Escribe con normalidad").font(.system(size: 16, weight: .semibold)).foregroundStyle(Halo.texto)
                Text("Lo que quieras, a tu ritmo. Hazlo con calma: una tecla a la vez suena mejor.")
                    .font(.system(size: 12)).foregroundStyle(Halo.texto2).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Regla(valor: 1 - Double(s) / Double(SesionTeclado.segundosLibres), tono: .azul, cuantas: 40, alto: 10)
                    Text("\(s) s").font(.system(size: 11.5, weight: .semibold)).monospacedDigit().foregroundStyle(Halo.texto2).frame(width: 34, alignment: .trailing)
                }
                Text("\(sesion.teclasOidas) teclas oídas").font(Halo.detalle).foregroundStyle(Halo.texto3)
            }
        case .guiada(let clase, let hechas):
            VStack(alignment: .leading, spacing: 10) {
                Text("Pulsa \(nombre(clase)) \(SesionTeclado.pulsacionesGuiadas) veces").font(.system(size: 16, weight: .semibold)).foregroundStyle(Halo.texto)
                Text("Una pulsación a la vez, con una pausa corta entre cada una.").font(.system(size: 12)).foregroundStyle(Halo.texto2)
                HStack(spacing: 8) {
                    ForEach(0..<SesionTeclado.pulsacionesGuiadas, id: \.self) { i in
                        Circle().fill(i < hechas ? Tono.azul.claro : Color.white.opacity(0.14)).frame(width: 14, height: 14)
                            .shadow(color: i < hechas ? Tono.azul.base : .clear, radius: 4)
                    }
                    Spacer()
                    Text("\(hechas) de \(SesionTeclado.pulsacionesGuiadas)").font(.system(size: 11.5, weight: .semibold)).monospacedDigit().foregroundStyle(Halo.texto2)
                }
            }
        case .procesando:
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("Cortando y ordenando los sonidos…").font(.system(size: 12.5)).foregroundStyle(Halo.texto2)
            }
        case .listo(let m):
            Label { Text(m).font(.system(size: 13)).foregroundStyle(Halo.texto).fixedSize(horizontal: false, vertical: true) }
                icon: { Image(systemName: "checkmark.circle.fill").foregroundStyle(Tono.verde.claro) }
        case .fallo(let m):
            Label { Text(m).font(.system(size: 12.5)).foregroundStyle(Halo.texto).fixedSize(horizontal: false, vertical: true) }
                icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Tono.ambar.claro) }
        }
    }

    private func paso(_ n: String, _ texto: String) -> some View {
        HStack(spacing: 10) {
            Text(n).font(.system(size: 11, weight: .bold)).foregroundStyle(.black).frame(width: 20, height: 20).background(Circle().fill(Tono.azul.claro))
            Text(texto).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Halo.texto)
        }
    }

    private func nombre(_ c: ClaseTecla) -> String {
        switch c {
        case .espacio: return "Espacio"
        case .intro: return "Intro"
        case .retroceso: return "Retroceso"
        case .normal: return "una tecla"
        }
    }

    @ViewBuilder private var pie: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            switch sesion.fase {
            case .inicio:
                BotonHalo(titulo: "Cancelar", secundario: true, alto: 30) { cerrar() }
                BotonHalo(titulo: "Empezar", icono: "record.circle", alto: 30) { sesion.empezar() }
            case .cuenta, .libre, .guiada:
                BotonHalo(titulo: "Cancelar", secundario: true, alto: 30) { sesion.cancelar(); cerrar() }
            case .procesando:
                EmptyView()
            case .listo:
                BotonHalo(titulo: "Listo", icono: "checkmark", alto: 30) { cerrar() }
            case .fallo:
                BotonHalo(titulo: "Cerrar", secundario: true, alto: 30) { cerrar() }
                BotonHalo(titulo: "Reintentar", alto: 30) { sesion.fase = .inicio }
            }
        }
        .frame(height: 30)
    }
}

/// Para los renders: el panel en varios momentos, sobre el fondo de muestra (`--vista-teclado`).
@MainActor
func hojaGrabarTeclado(_ destino: URL) -> Bool {
    let fondo = fondoDeMuestra()
    func panel(_ fase: SesionTeclado.Fase, teclas: Int = 0) -> some View {
        lienzoConVidrio(fondo, lienzo: CGSize(width: 560, height: 390), panel: CGSize(width: VistaGrabarTeclado.ancho, height: VistaGrabarTeclado.alto), radio: 28) {
            VistaGrabarTeclado(sesion: SesionTeclado(fase: fase, teclas: teclas), simulado: true)
        }
    }
    let hoja = VStack(spacing: 0) {
        HStack(spacing: 0) { panel(.inicio); panel(.libre(restante: 12), teclas: 57) }
        HStack(spacing: 0) { panel(.guiada(.intro, hechas: 3), teclas: 71); panel(.listo("Listo: 22 sonidos al pulsar y 19 al soltar. Ya suena tu teclado.")) }
        HStack(spacing: 0) {
            panel(.fallo("Falta el permiso de Micrófono para Dictado. Actívalo en Ajustes del Sistema → Privacidad y seguridad → Micrófono y vuelve a abrir esta ventana."))
            panel(.fallo("Salieron solo 7 sonidos al pulsar y 6 al soltar de 12 necesarios: escribe con calma, sin pulsar dos teclas a la vez, y repite."))
        }
    }
    let renderer = ImageRenderer(content: hoja)
    renderer.scale = 1.5
    guard let cg = renderer.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return false }
    return (try? png.write(to: destino)) != nil
}
