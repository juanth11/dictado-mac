import AppKit
import ApplicationServices
import Carbon.HIToolbox
import DictadoKit
import os

private let log = Logger(subsystem: "app.dictado", category: "teclas")

// Teclas: un sonido de interruptor mecánico en cada tecla, con sonido al pulsar y otro (más ligero) al soltar, un
// tono apenas distinto cada vez, el estéreo según dónde está la tecla en el teclado, varios perfiles y volumen propio.
// El audio se sintetiza al abrir (DictadoKit/SintesisTeclas.swift) o, si lo grabaste («Grabar mi teclado…», TecladoGrabar.swift),
// sale de los recortes de tu propio teclado en ~/Library/Application Support/Dictado/teclas/mi-teclado/. No hay descargas.
//
// Qué lee: solo el código de cada tecla y si bajó o subió. Nunca el carácter; no se guarda ni se registra nada.
// Se calla solo mientras dictas o grabas una reunión, y con Entrada segura activa (campos de contraseña).
//
// El teclado se escucha con su propio event tap de sesión, en un hilo aparte, que deja pasar cada evento sin tocarlo.
// No se reutilizó el de la tecla hyper: ese solo existe con hyper encendida y filtra el teclado a nivel HID; este es
// independiente y pasivo, así que Teclas funciona con o sin hyper y un fallo de una no afecta a la otra.
// Pide Accesibilidad, igual que hyper, ventanas y buscador.
//
// Ajustes en el dominio app.dictado:
//   defaults write app.dictado teclas.perfil mi-teclado|thock|clack|crema|burbuja
//       (sin ajuste, suena «Mi teclado» si ya lo grabaste y, si no, thock)
//   defaults write app.dictado teclas.volumen -float 0.4       (0 a 1, aparte del volumen del Mac)
//   defaults write app.dictado teclas.alSoltar -bool false     (sin sonido al soltar)
//   defaults write app.dictado teclas.variacion -float 0.5     (0 a 1: cuánto cambia el tono en cada tecla)
//   defaults write app.dictado teclas.espacial -bool false     (todo al centro)

struct OpcionesTeclas {
    private let d = UserDefaults.dictado
    /// El perfil sintetizado (el de respaldo si «Mi teclado» no está).
    var perfil: PerfilTeclas { PerfilTeclas(rawValue: d.string(forKey: "teclas.perfil") ?? "") ?? .thock }
    /// «Mi teclado» suena si lo elegiste o, sin elección, en cuanto existe.
    var usaMiTeclado: Bool {
        let elegido = d.string(forKey: "teclas.perfil")
        return elegido == "mi-teclado" || (elegido == nil && AlmacenTeclado.existe())
    }
    var volumen: Float { d.object(forKey: "teclas.volumen") == nil ? 0.4 : min(max(d.float(forKey: "teclas.volumen"), 0), 1) }
    var alSoltar: Bool { d.object(forKey: "teclas.alSoltar") as? Bool ?? true }
    var variacion: Float { d.object(forKey: "teclas.variacion") == nil ? 0.5 : min(max(d.float(forKey: "teclas.variacion"), 0), 1) }
    var espacial: Bool { d.object(forKey: "teclas.espacial") as? Bool ?? true }
    func poner(_ clave: String, _ valor: Any) { d.set(valor, forKey: "teclas." + clave) }
    var motor: MotorTeclas.Ajustes {
        MotorTeclas.Ajustes(volumen: volumen, alSoltar: alSoltar, variacion: variacion, espacial: espacial)
    }
}

/// Un Bool que se lee desde el hilo del tap y se escribe desde el principal.
private final class Bandera: @unchecked Sendable {
    private let c = NSLock()
    private var v = false
    var valor: Bool {
        get { c.withLock { v } }
        set { c.withLock { v = newValue } }
    }
}

@MainActor
final class Teclas: NSObject, NSMenuDelegate {
    static let shared = Teclas()
    static var itemMenu: NSMenuItem { shared.item }

    static func instalar(_ contexto: ContextoModulos) -> Teclas {
        shared.contexto = contexto
        shared.arrancar()
        return shared
    }

    private static let idAtajo: UInt32 = 63

    private var contexto: ContextoModulos?
    private var opciones = OpcionesTeclas()
    private let motor = MotorTeclas()
    private let tap = TapTeclas()
    private let silencio = Bandera()
    /// Mientras se graba «Mi teclado», nada suena (el micrófono oiría la síntesis).
    private let grabando = Bandera()
    private var arrancado = false
    private var encendido = false
    private var perfilCargado: String?
    private var atajoPuesto = false
    private let menu = NSMenu()
    private lazy var item: NSMenuItem = {
        let i = NSMenuItem(title: "Teclas con sonido", action: nil, keyEquivalent: "")
        menu.delegate = self
        i.submenu = menu
        return i
    }()

    private func arrancar() {
        guard !arrancado else { return }
        arrancado = true
        NotificationCenter.default.addObserver(forName: .funcionesCambiaron, object: nil, queue: .main) { [weak self] nota in
            guard (nota.userInfo?["funcion"] as? String) == Funcion.teclas.rawValue else { return }
            MainActor.assumeIsolated { self?.sincronizar() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.apagar() }
        }
        motor.alFallar = { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.contexto?.avisar("Teclas: se perdió el audio", "speaker.slash", nil) } }
        }
        GrabarTeclado.shared.silenciar = { [weak self] si in self?.grabando.valor = si }
        GrabarTeclado.shared.alGuardar = { [weak self] in
            self?.opciones.poner("perfil", "mi-teclado")   // Mi teclado pasa a ser el sonido
            self?.recargar(muestra: false)
        }
        sincronizar()
    }

    private func sincronizar() {
        if Funcion.teclas.activa {
            registrarAtajo()
            encender()
        } else {
            apagar()
            quitarAtajo()
        }
    }

    private func encender() {
        guard !encendido else { return }
        opciones = OpcionesTeclas()
        motor.configurar(opciones.motor)
        encendido = true
        // Los buffers se arman (y los WAV de «Mi teclado» se leen) fuera del hilo principal; el motor arranca cuando están.
        let miTeclado = opciones.usaMiTeclado, perfil = opciones.perfil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let cargado = Self.preparar(motor: self.motor, miTeclado: miTeclado, perfil: perfil)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.terminarEncendido(cargado) }
            }
        }
    }

    /// Arma el sonido en el motor: «Mi teclado» si hay (y se lee bien) y, si no, el perfil sintetizado. Devuelve cuál quedó.
    nonisolated private static func preparar(motor: MotorTeclas, miTeclado: Bool, perfil: PerfilTeclas) -> String {
        if miTeclado, let juego = AlmacenTeclado.cargar(desde: AlmacenTeclado.carpetaPorOmision()) {
            motor.preparar(grabado: juego)
            return "mi-teclado"
        }
        motor.preparar(perfil)
        return perfil.rawValue
    }

    private func terminarEncendido(_ cargado: String) {
        guard encendido else { return }
        perfilCargado = cargado
        guard motor.arrancar() else {
            contexto?.avisar("Teclas: no pude abrir la salida de audio", "speaker.slash", nil)
            encendido = false
            return
        }
        conectarTap()
    }

    private func conectarTap() {
        guard encendido, !tap.activo else { return }
        guard AXIsProcessTrusted() else {
            contexto?.avisar("Teclas necesita Accesibilidad para oír el teclado", "lock", nil)
            return
        }
        let motor = self.motor, silencio = self.silencio, grabando = self.grabando
        let dictando = contexto?.dictando
        let ok = tap.iniciar { codigo, abajo, repeticion in
            if repeticion { return }  // la repetición automática no vuelve a sonar
            if abajo, let dictando {
                // El estado de dictado vive en el hilo principal: se refresca con cada pulsación y vale desde la siguiente.
                DispatchQueue.main.async { silencio.valor = MainActor.assumeIsolated { dictando() } }
            }
            if MapaTeclas.silenciosa(codigo: codigo) || silencio.valor || grabando.valor { return }
            motor.cola.async {
                if Self.entradaSegura() { return }
                motor.sonar(codigo: codigo, abajo: abajo)
            }
        }
        if !ok { contexto?.avisar("Teclas no pudo escuchar el teclado", "keyboard.badge.exclamationmark", nil) }
    }

    /// `IsSecureEventInputEnabled` se consulta como máximo cada medio segundo (solo se llama desde la cola de audio).
    nonisolated(unsafe) private static var ultimaConsulta = 0.0
    nonisolated(unsafe) private static var ultimaSegura = false
    nonisolated private static func entradaSegura() -> Bool {
        let ahora = ProcessInfo.processInfo.systemUptime
        if ahora - ultimaConsulta > 0.5 {
            ultimaConsulta = ahora
            ultimaSegura = IsSecureEventInputEnabled()
        }
        return ultimaSegura
    }

    private func apagar() {
        guard encendido else { return }
        encendido = false
        tap.detener()
        motor.parar()
        silencio.valor = false
    }

    // MARK: Atajo

    private func registrarAtajo() {
        guard !atajoPuesto else { return }
        let hyper = cmdKey | optionKey | controlKey | shiftKey
        atajoPuesto = Atajos.shared.registrar(id: Self.idAtajo, tecla: kVK_ANSI_K, modificadores: hyper,
                                              alPresionar: { Funcion.teclas.poner(!Funcion.teclas.activa) })
        if !atajoPuesto { contexto?.avisar("Hyper + K lo usa otra app", "keyboard.badge.exclamationmark", nil) }
    }

    private func quitarAtajo() {
        guard atajoPuesto else { return }
        atajoPuesto = false
        Atajos.shared.quitar(id: Self.idAtajo)
    }

    // MARK: Menú

    func menuNeedsUpdate(_ menu: NSMenu) {
        opciones = OpcionesTeclas()
        menu.removeAllItems()
        // Si faltaba Accesibilidad al encender y ya la diste, se conecta al abrir el menú.
        if encendido, !tap.activo, AXIsProcessTrusted() { conectarTap() }
        guard Funcion.teclas.activa else {
            let i = NSMenuItem(title: "Apagado: enciéndelo en Funciones → Teclas con sonido", action: nil, keyEquivalent: "")
            i.isEnabled = false
            menu.addItem(i)
            return
        }
        let hayMiTeclado = AlmacenTeclado.existe()
        func agregar(_ titulo: String, marcado: Bool = false, sangria: Int = 0, _ accion: @escaping () -> Void) {
            let i = NSMenuItem(title: titulo, action: #selector(ejecutarItem(_:)), keyEquivalent: "")
            i.target = self
            i.state = marcado ? .on : .off
            i.indentationLevel = sangria
            i.representedObject = AccionTecla(accion)
            menu.addItem(i)
        }
        func titulo(_ t: String) {
            let i = NSMenuItem(title: t, action: nil, keyEquivalent: "")
            i.isEnabled = false
            menu.addItem(i)
        }
        agregar("Apagar las teclas con sonido  (Hyper + K)") { Funcion.teclas.poner(false) }
        titulo("Sonido")
        if hayMiTeclado {
            agregar("Mi teclado (grabado)", marcado: opciones.usaMiTeclado, sangria: 1) { [weak self] in self?.elegirMiTeclado() }
        }
        for p in PerfilTeclas.allCases {
            agregar(p.nombre, marcado: !opciones.usaMiTeclado && opciones.perfil == p, sangria: 1) { [weak self] in self?.elegirPerfil(p) }
        }
        titulo("Volumen")
        for (t, v) in [("25 %", Float(0.25)), ("50 %", 0.5), ("75 %", 0.75), ("100 %", 1.0)] {
            agregar(t, marcado: abs(opciones.volumen - v) < 0.125, sangria: 1) { [weak self] in self?.fijar("volumen", v) }
        }
        titulo("Variación de tono")
        for (t, v) in [("Ninguna", Float(0)), ("Poca", 0.5), ("Mucha", 1.0)] {
            agregar(t, marcado: abs(opciones.variacion - v) < 0.26, sangria: 1) { [weak self] in self?.fijar("variacion", v) }
        }
        menu.addItem(.separator())
        agregar("Sonido al soltar la tecla", marcado: opciones.alSoltar) { [weak self] in
            guard let self else { return }
            self.fijar("alSoltar", !self.opciones.alSoltar)
        }
        agregar("Estéreo según la tecla", marcado: opciones.espacial) { [weak self] in
            guard let self else { return }
            self.fijar("espacial", !self.opciones.espacial)
        }
        menu.addItem(.separator())
        agregar(hayMiTeclado ? "Volver a grabar mi teclado…" : "Grabar mi teclado…") { GrabarTeclado.shared.abrir() }
        if hayMiTeclado {
            agregar("Borrar mi teclado") { [weak self] in self?.borrarMiTeclado() }
        }
    }

    private final class AccionTecla: NSObject {
        let accion: () -> Void
        init(_ a: @escaping () -> Void) { accion = a }
    }

    @objc private func ejecutarItem(_ i: NSMenuItem) { (i.representedObject as? AccionTecla)?.accion() }

    private func fijar(_ clave: String, _ valor: Any) {
        opciones.poner(clave, valor)
        opciones = OpcionesTeclas()
        motor.configurar(opciones.motor)
    }

    /// Cambia de perfil y deja oír una pulsación de muestra (la eliges tú, en el menú).
    private func elegirPerfil(_ p: PerfilTeclas, muestra: Bool = true) {
        opciones.poner("perfil", p.rawValue)
        recargar(muestra: muestra)
    }

    private func elegirMiTeclado() {
        opciones.poner("perfil", "mi-teclado")
        recargar(muestra: true)
    }

    /// Borra los sonidos grabados; si «Mi teclado» era el sonido, vuelve al thock.
    private func borrarMiTeclado() {
        AlmacenTeclado.borrar()
        if UserDefaults.dictado.string(forKey: "teclas.perfil") == "mi-teclado" { opciones.poner("perfil", PerfilTeclas.thock.rawValue) }
        recargar(muestra: false)
    }

    /// Vuelve a armar el sonido elegido fuera del hilo principal, y deja oír una pulsación si `muestra`.
    private func recargar(muestra: Bool) {
        guard encendido else { return }
        let o = OpcionesTeclas()
        let miTeclado = o.usaMiTeclado, perfil = o.perfil
        DispatchQueue.global(qos: .userInitiated).async { [weak self, motor] in
            let cargado = Self.preparar(motor: motor, miTeclado: miTeclado, perfil: perfil)
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.perfilCargado = cargado } }
            motor.cola.async {
                guard muestra else { return }
                motor.sonar(codigo: 0, abajo: true)
                motor.sonar(codigo: 0, abajo: false)
            }
        }
    }

    /// Cambia el perfil sin sonido de muestra (lo usa un espacio de Inicio al activarse).
    func cambiarPerfil(_ p: PerfilTeclas) { elegirPerfil(p, muestra: false) }
}

// MARK: - Event tap pasivo en hilo propio

/// Escucha keyDown/keyUp con un tap de sesión que deja pasar todo. Lo crea y lo atiende en su propio hilo (así el
/// teclado del Mac no depende de que el hilo principal esté libre). Solo lee el código de tecla y si es repetición.
final class TapTeclas: @unchecked Sendable {
    typealias Manejador = @Sendable (_ codigo: Int, _ abajo: Bool, _ repeticion: Bool) -> Void

    private final class Sesion: @unchecked Sendable {
        var tap: CFMachPort?
        var bucle: CFRunLoop?
        let manejador: Manejador
        init(_ m: @escaping Manejador) { manejador = m }

        func manejar(_ tipo: CGEventType, _ evento: CGEvent) -> Unmanaged<CGEvent>? {
            switch tipo {
            case .tapDisabledByTimeout, .tapDisabledByUserInput:
                if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            case .keyDown, .keyUp:
                manejador(Int(evento.getIntegerValueField(.keyboardEventKeycode)), tipo == .keyDown,
                          evento.getIntegerValueField(.keyboardEventAutorepeat) != 0)
            default: break
            }
            return Unmanaged.passUnretained(evento)
        }
    }

    private(set) var activo = false
    private var sesion: Sesion?
    private static let mascara: CGEventMask = [CGEventType.keyDown, .keyUp].reduce(0) { $0 | (CGEventMask(1) << $1.rawValue) }

    @MainActor
    func iniciar(_ manejador: @escaping Manejador) -> Bool {
        guard !activo else { return true }
        let s = Sesion(manejador)
        let listo = DispatchSemaphore(value: 0)
        let hilo = Thread {
            let refcon = Unmanaged.passUnretained(s).toOpaque()
            if let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: TapTeclas.mascara,
                callback: { _, tipo, evento, refcon in
                    guard let refcon else { return Unmanaged.passUnretained(evento) }
                    return Unmanaged<Sesion>.fromOpaque(refcon).takeUnretainedValue().manejar(tipo, evento)
                }, userInfo: refcon) {
                s.tap = tap
                s.bucle = CFRunLoopGetCurrent()
                CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            let vivo = s.bucle != nil
            listo.signal()
            if vivo { CFRunLoopRun() }  // duerme hasta que llegue una tecla
        }
        hilo.name = "app.dictado.teclas"
        hilo.qualityOfService = .userInteractive
        hilo.start()
        listo.wait()
        guard s.bucle != nil else { return false }
        sesion = s
        activo = true
        return true
    }

    @MainActor
    func detener() {
        guard activo, let s = sesion, let bucle = s.bucle else { return }
        activo = false
        sesion = nil
        CFRunLoopPerformBlock(bucle, CFRunLoopMode.commonModes.rawValue) {
            if let tap = s.tap {
                CGEvent.tapEnable(tap: tap, enable: false)
                CFMachPortInvalidate(tap)
            }
            s.tap = nil
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
        CFRunLoopWakeUp(bucle)
    }
}
