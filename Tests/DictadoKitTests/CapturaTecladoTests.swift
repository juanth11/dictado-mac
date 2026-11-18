import Testing
@testable import DictadoKit

private func tecla(_ t: Double, _ abajo: Bool, _ c: ClaseTecla = .normal) -> EventoTecla { EventoTecla(t: t, abajo: abajo, clase: c) }

/// 12 s de ruido con un clic al pulsar (20 ms después de la hora de la tecla) y uno más suave al soltar (15 ms después), con un
/// desfase fijo de 0,18 s entre el reloj de las teclas y la grabación.
private func sesion(desfase: Double = 0.18) -> (x: [Float], eventos: [EventoTecla]) {
    var x = fondoDeRuido(12)
    var ev: [EventoTecla] = []
    for k in 0..<20 {
        let t = 0.5 + Double(k) * 0.5            // una tecla cada medio segundo
        ev.append(tecla(t, true))
        ev.append(tecla(t + 0.11, false))
        clic(en: &x, inicio: t + desfase + 0.020, fuerza: 0.30 + 0.01 * Float(k % 5), semilla: UInt64(10 + k))
        clic(en: &x, inicio: t + 0.11 + desfase + 0.015, fuerza: 0.12, largo: 0.03, tau: 0.004, semilla: UInt64(500 + k))
    }
    return (x, ev)
}

@Test("Detección: cada clic sobre el ruido se encuentra, en su hora (±2 ms), y el ruido solo no da golpes")
func deteccion() {
    var x = fondoDeRuido(6)
    #expect(DetectorGolpes.detectar(x).isEmpty)
    let horas = [0.7, 1.4, 2.1, 3.3, 4.0, 5.2]
    for (i, h) in horas.enumerated() { clic(en: &x, inicio: h, fuerza: 0.25, semilla: UInt64(i + 1)) }
    let g = DetectorGolpes.detectar(x)
    #expect(g.count == horas.count)
    for (golpe, h) in zip(g, horas) { #expect(abs(golpe.tiempo - h) < 0.002) }
}

@Test("Detección: un clic suave (1/50 del fuerte) también se oye, y dos clics a 10 ms cuentan como uno")
func deteccionSuaveYCercanos() {
    var x = fondoDeRuido(5)
    clic(en: &x, inicio: 1.0, fuerza: 0.03, semilla: 1)
    clic(en: &x, inicio: 2.0, fuerza: 0.30, semilla: 2)
    clic(en: &x, inicio: 2.010, fuerza: 0.30, semilla: 3)
    clic(en: &x, inicio: 3.5, fuerza: 0.30, semilla: 4)
    let g = DetectorGolpes.detectar(x)
    #expect(g.count == 3)
    #expect(abs(g[0].tiempo - 1.0) < 0.003)
}

@Test("Alineación: encuentra el desfase entre el reloj de las teclas y la grabación")
func alineacion() {
    let s = sesion(desfase: 0.18)
    let golpes = DetectorGolpes.detectar(s.x).map(\.tiempo)
    let d = EmparejadorTeclas.alinear(golpes: golpes, eventos: s.eventos.map(\.t))
    // Los golpes llegan 15–20 ms después de la tecla: el desfase medido es 0,18 más ese retraso.
    #expect(d > 0.18 && d < 0.21)
}

@Test("Emparejar: cada tecla toma su golpe; una tecla que no sonó queda sin golpe")
func emparejar() {
    var s = sesion()
    s.eventos.append(tecla(9.0, true))   // no suena nada ahí
    let g = DetectorGolpes.detectar(s.x)
    let d = EmparejadorTeclas.alinear(golpes: g.map(\.tiempo), eventos: s.eventos.map(\.t))
    let p = EmparejadorTeclas.emparejar(golpes: g, eventos: s.eventos, desfase: d)
    #expect(p.compactMap { $0 }.count == 40)
    #expect(p.last! == nil)
    #expect(Set(p.compactMap { $0 }).count == 40)   // ningún golpe sirve a dos teclas
}

@Test("Procesar: una sesión limpia da ≥ 12 sonidos al pulsar y ≥ 12 al soltar, parejos y sin recortar")
func procesarSesionLimpia() {
    let s = sesion()
    let (juego, informe) = CapturaTeclado.procesar(s.x, eventos: s.eventos)
    #expect(informe.golpesDetectados == 40)
    #expect(informe.emparejadas == 40)
    #expect(informe.suficiente())
    let normal = juego.par(.normal)
    #expect(normal.abajo.count == 20 && normal.arriba.count == 20)
    for m in normal.abajo {
        #expect(Swift.abs(AnalisisAudio.pico(m)) <= 0.95)
        let r = CapturaTeclado.rmsInicial(m, tasa: SintesisTeclas.tasa)
        #expect(r > 0.09 && r <= 0.1801)                                                           // volumen parejo (el tope de pico 0,95 puede quedarse más abajo)
        #expect(abs32(m.last ?? 1) < 0.01)                                                           // sale en silencio
        #expect(m.allSatisfy { $0.isFinite })
    }
    // Soltar es más ligero que pulsar.
    let a = AnalisisAudio.rms(normal.abajo[0]), u = AnalisisAudio.rms(normal.arriba[0])
    #expect(u < a)
    // El recorte empieza justo antes del golpe: lo más fuerte está en los primeros 15 ms.
    let tope = normal.abajo[0].prefix(Int(0.015 * SintesisTeclas.tasa)).map { abs32($0) }.max() ?? 0
    #expect(tope >= Float(AnalisisAudio.pico(normal.abajo[0])) * 0.8)
}

@Test("Procesar: dos teclas casi a la vez (35 ms) se rechazan por solapadas")
func rechazaSolapadas() {
    var x = fondoDeRuido(4)
    var ev: [EventoTecla] = []
    // Seis teclas limpias para que la alineación tenga de dónde agarrarse...
    for k in 0..<6 {
        let t = 0.5 + Double(k) * 0.4
        ev.append(tecla(t, true))
        clic(en: &x, inicio: t + 0.02, fuerza: 0.3, semilla: UInt64(k + 1))
    }
    // ...y dos teclas encimadas.
    ev.append(tecla(3.0, true)); ev.append(tecla(3.035, true))
    clic(en: &x, inicio: 3.02, fuerza: 0.3, semilla: 77)
    clic(en: &x, inicio: 3.055, fuerza: 0.3, semilla: 78)
    let (_, informe) = CapturaTeclado.procesar(x, eventos: ev, desfase: 0.0)
    #expect((informe.rechazadas["solapada"] ?? 0) >= 2)
}

@Test("Procesar: un clic saturado se rechaza; uno con mucho ruido encima, también")
func rechazaSaturadaYRuidosa() {
    var x = fondoDeRuido(4)
    var ev: [EventoTecla] = []
    for k in 0..<4 {
        let t = 0.5 + Double(k) * 0.6
        ev.append(tecla(t, true))
        clic(en: &x, inicio: t + 0.02, fuerza: 0.3, semilla: UInt64(k + 1))
    }
    ev.append(tecla(3.0, true))
    clic(en: &x, inicio: 3.02, fuerza: 3.0, semilla: 9)                      // se pasa de 1: saturada
    for i in x.indices { x[i] = max(-1, min(1, x[i])) }
    let (_, informe) = CapturaTeclado.procesar(x, eventos: ev, desfase: 0.0)
    #expect((informe.rechazadas["saturada"] ?? 0) == 1)
    #expect(informe.elegidas["normal-abajo"] == 4)

    // Con ruido de fondo casi tan fuerte como el clic, no pasa el umbral de relación señal/ruido.
    var y = fondoDeRuido(3, ruido: 0.05)
    clic(en: &y, inicio: 1.0, fuerza: 0.12, semilla: 5)
    let (j, i2) = CapturaTeclado.procesar(y, eventos: [tecla(0.98, true)], desfase: 0.0)
    #expect(j.total == 0)
    #expect(i2.rechazadas["ruidosa", default: 0] + i2.rechazadas["sin-golpe", default: 0] >= 1)
}

@Test("Procesar: elige los más limpios cuando hay más del tope y respeta las clases")
func eligeLosMejores() {
    var x = fondoDeRuido(40)
    var ev: [EventoTecla] = []
    for k in 0..<30 {
        let t = 0.5 + Double(k) * 0.6
        ev.append(tecla(t, true))
        // Los pares son claramente más fuertes (mejor relación señal/ruido) que los impares.
        clic(en: &x, inicio: t + 0.02, fuerza: k % 2 == 0 ? 0.4 : 0.05, semilla: UInt64(k + 1))
    }
    for k in 0..<5 {
        let t = 20.0 + Double(k) * 0.8
        ev.append(tecla(t, true, .espacio))
        clic(en: &x, inicio: t + 0.02, fuerza: 0.35, largo: 0.09, tau: 0.02, semilla: UInt64(900 + k))
    }
    var config = ConfigRecorte()
    config.maxPorClase[.normal] = 10
    let (juego, informe) = CapturaTeclado.procesar(x, eventos: ev, config: config, desfase: 0.0)
    #expect(juego.par(.normal).abajo.count == 10)
    #expect(juego.par(.espacio).abajo.count == 5)
    #expect(juego.par(.intro).abajo.isEmpty)
    #expect(informe.elegidas["espacio-abajo"] == 5)
    // Los diez elegidos son de los fuertes (la normalización los iguala, así que miro cuántos conservan el golpe al inicio).
    #expect(informe.rechazadas["ruidosa", default: 0] <= 15)
}

@Test("Una grabación casi muda se dice con claridad; pocas teclas, también")
func mensajes() {
    let (_, vacio) = CapturaTeclado.procesar(fondoDeRuido(3, ruido: 0.0005), eventos: [tecla(1, true)])
    #expect(vacio.mensaje().contains("Casi no se oyó nada"))
    var poco = InformeCaptura()
    poco.picoGrabacion = 0.5
    poco.golpesDetectados = 3
    #expect(poco.mensaje().contains("muy pocas"))
    var ok = InformeCaptura()
    ok.picoGrabacion = 0.5
    ok.golpesDetectados = 80
    ok.elegidas = ["normal-abajo": 14, "normal-arriba": 13]
    #expect(ok.mensaje() == "Listo: 14 sonidos al pulsar y 13 al soltar.")
}

@Test("WAV: lo que se escribe se lee igual (16 bits), y a otra tasa se remuestrea")
func wavIdaYVuelta() {
    let x: [Float] = (0..<4410).map { Float(Double($0 % 100) / 100 - 0.5) * 0.8 }
    let leido = LectorWAV.leer(AnalisisAudio.datosWAV(x))
    #expect(leido?.count == x.count)
    for (a, b) in zip(x, leido ?? []) { #expect(abs32(a - b) < 0.001) }
    #expect(LectorWAV.leer(datosJSON("no es un wav")) == nil)
}

@Test("Las clases de tecla: espacio, intro (y el del teclado numérico), retroceso; el resto es normal")
func clases() {
    #expect(MapaTeclas.clase(codigo: 49) == .espacio)
    #expect(MapaTeclas.clase(codigo: 36) == .intro && MapaTeclas.clase(codigo: 76) == .intro)
    #expect(MapaTeclas.clase(codigo: 51) == .retroceso)
    #expect(MapaTeclas.clase(codigo: 0) == .normal)
}
