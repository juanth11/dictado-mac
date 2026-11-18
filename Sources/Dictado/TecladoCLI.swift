import DictadoKit
import Foundation

/// `Dictado --teclado-wav grabacion.wav teclas.json [carpeta]`: corta «Mi teclado» de una grabación ya hecha, sin abrir el micrófono
/// ni reproducir nada. `teclas.json` es `{"desfase": 0.18, "eventos": [{"t": 1.2, "abajo": true, "clase": "normal"}, ...]}` (`t` en
/// segundos desde el inicio de la grabación; `desfase` es opcional: sin él se calcula). Escribe los recortes como WAV en `carpeta`
/// (por omisión /tmp/dictado-mi-teclado) y un informe numérico. Termina con 0 si salieron suficientes sonidos y con 2 si no.
func cortarTecladoDeArchivo(wav: URL, json: URL, carpeta: URL) -> Int32 {
    struct Entrada: Decodable {
        var desfase: Double?
        var eventos: [EventoTecla]
    }
    guard let datos = try? Data(contentsOf: wav), let x = LectorWAV.leer(datos) else {
        print("no pude leer el WAV: \(wav.path)")
        return 1
    }
    guard let j = try? Data(contentsOf: json), let entrada = try? JSONDecoder().decode(Entrada.self, from: j) else {
        print("no pude leer el JSON de teclas: \(json.path)")
        return 1
    }
    let t0 = Date()
    let (juego, informe) = CapturaTeclado.procesar(x, eventos: entrada.eventos, desfase: entrada.desfase)
    do { try AlmacenTeclado.guardar(juego, en: carpeta) } catch {
        print("no pude escribir en \(carpeta.path): \(error.localizedDescription)")
        return 1
    }
    print(String(format: "grabación: %.1f s · procesada en %.2f s", Double(x.count) / SintesisTeclas.tasa, Date().timeIntervalSince(t0)))
    print(informe.reporte)
    print("sonidos escritos: \(juego.total) en \(carpeta.path)")
    print("loudness (RMS de los primeros 40 ms) y centroide por clase:")
    for clase in ClaseTecla.allCases {
        for (dir, lista) in [("abajo", juego.par(clase).abajo), ("arriba", juego.par(clase).arriba)] where !lista.isEmpty {
            let r = lista.map { CapturaTeclado.rmsInicial($0, tasa: SintesisTeclas.tasa) }
            let c = lista.map { AnalisisAudio.centroide($0) }
            print(String(format: "  %-9@ %-6@ n=%2d  RMS %.3f–%.3f  centroide %.0f Hz  pico máx %.2f", clase.rawValue as NSString, dir as NSString, lista.count,
                         r.min() ?? 0, r.max() ?? 0, c.reduce(0, +) / Double(c.count), lista.map { AnalisisAudio.pico($0) }.max() ?? 0))
        }
    }
    let ok = informe.suficiente()
    print(ok ? "suficiente: sí (≥ 12 al pulsar y ≥ 12 al soltar)" : "suficiente: no — " + informe.mensaje())
    return ok ? 0 : 2
}

/// `Dictado --teclado-demo carpeta`: escribe una grabación inventada (ruido con clics en horas conocidas) y su JSON de teclas, para
/// probar `--teclado-wav` de punta a punta sin micrófono.
func escribirTecladoDemo(_ carpeta: URL) -> Bool {
    do { try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true) } catch { return false }
    let tasa = SintesisTeclas.tasa
    var azar = Azar(semilla: 4242)
    var x = (0..<Int(34 * tasa)).map { _ in Float(azar.siguiente()) * 0.005 }
    var eventos: [EventoTecla] = []
    let desfase = 0.12
    func clic(_ t: Double, _ fuerza: Float, largo: Double, tau: Double) {
        var a = Azar(semilla: UInt64(t * 1000) &+ 7)
        let i0 = Int(t * tasa)
        for i in 0..<Int(largo * tasa) where i0 + i < x.count { x[i0 + i] += fuerza * Float(exp(-Double(i) / tasa / tau) * a.siguiente()) }
    }
    var t = 1.0
    for k in 0..<45 {  // 20 s de teclas normales, a ritmos desparejos
        eventos.append(EventoTecla(t: t, abajo: true, clase: .normal))
        eventos.append(EventoTecla(t: t + 0.09, abajo: false, clase: .normal))
        clic(t + desfase + 0.018, 0.25 + 0.05 * Float(k % 4), largo: 0.06, tau: 0.007)
        clic(t + 0.09 + desfase + 0.012, 0.10, largo: 0.04, tau: 0.004)
        t += 0.35 + 0.15 * Double(k % 3)
    }
    t += 1.0
    for clase in [ClaseTecla.espacio, .intro, .retroceso] {
        for _ in 0..<5 {
            eventos.append(EventoTecla(t: t, abajo: true, clase: clase))
            eventos.append(EventoTecla(t: t + 0.12, abajo: false, clase: clase))
            clic(t + desfase + 0.02, 0.35, largo: 0.1, tau: 0.02)
            clic(t + 0.12 + desfase + 0.015, 0.15, largo: 0.06, tau: 0.01)
            t += 0.8
        }
    }
    struct Salida: Encodable { var desfase: Double?; var eventos: [EventoTecla] }
    do {
        try AnalisisAudio.datosWAV(x).write(to: carpeta.appendingPathComponent("demo.wav"))
        try JSONEncoder().encode(Salida(desfase: nil, eventos: eventos)).write(to: carpeta.appendingPathComponent("demo.json"))
    } catch { return false }
    print("demo escrita en \(carpeta.path) (desfase real entre relojes: \(Int(desfase * 1000)) ms; el programa lo calcula solo)")
    return true
}
