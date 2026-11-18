import Testing
@testable import DictadoKit

// MARK: Fondo del lanzador

@Test("Fondo: mac, paleta e imagen se leen y se vuelven a escribir igual; un nombre suelto es paleta")
func fondoTexto() {
    #expect(FondoLanzador(texto: "mac") == .mac)
    #expect(FondoLanzador(texto: " Fondo del Mac ") == .mac)
    #expect(FondoLanzador(texto: "paleta:lagunaDurazno") == .paleta("lagunaDurazno"))
    #expect(FondoLanzador(texto: "bosqueLima") == .paleta("bosqueLima"))
    #expect(FondoLanzador(texto: "imagen:~/Pictures/a.jpg", home: "/Users/x") == .imagen("/Users/x/Pictures/a.jpg"))
    #expect(FondoLanzador(texto: "/tmp/b.png") == .imagen("/tmp/b.png"))
    #expect(FondoLanzador(texto: "") == nil)
    #expect(FondoLanzador(texto: "paleta:") == nil)
    for f in [FondoLanzador.mac, .paleta("terracota"), .imagen("/tmp/c.heic")] { #expect(FondoLanzador(texto: f.texto) == f) }
}

@Test("Fondo: el del espacio gana al global y sin nada vale el fondo del Mac")
func fondoResolver() {
    #expect(FondoLanzador.resolver(espacio: nil, global: nil) == .mac)
    #expect(FondoLanzador.resolver(espacio: nil, global: "paleta:terracota") == .paleta("terracota"))
    #expect(FondoLanzador.resolver(espacio: "imagen:/tmp/x.jpg", global: "paleta:terracota") == .imagen("/tmp/x.jpg"))
    #expect(FondoLanzador.resolver(espacio: "   ", global: "paleta:terracota") == .paleta("terracota"))
}

@Test("Fondo: la línea fondo: de espacios.txt se lee y un valor vacío se ignora")
func fondoEnEspacios() {
    let e = EspaciosIsla.leer("[Foco]\nfondo: paleta:bosqueLima\n\n[Trabajo]\nfondo:\n\n[Descanso]\nprimero: Spotify")
    #expect(e[0].fondo == "paleta:bosqueLima")
    #expect(e[1].fondo == nil)
    #expect(e[2].fondo == nil)
    #expect(EspaciosIsla.leer(EspaciosIsla.inicial).allSatisfy { $0.fondo == nil })
}

@Test("Fondo: conFondo pone, cambia y quita la línea solo en su espacio y deja el resto intacto")
func fondoEditarArchivo() {
    let base = "# nota\n[Trabajo]\nprimero: Mail\nvelo: no\n\n[Foco]\nprimero: Notas\n# fin\n"
    let puesto = EspaciosIsla.conFondo(base, espacio: "foco", fondo: .paleta("terracota"))
    #expect(puesto == "# nota\n[Trabajo]\nprimero: Mail\nvelo: no\n\n[Foco]\nprimero: Notas\nfondo: paleta:terracota\n# fin\n")
    #expect(EspaciosIsla.leer(puesto)[1].fondo == "paleta:terracota")
    #expect(EspaciosIsla.leer(puesto)[0].fondo == nil)
    let cambiado = EspaciosIsla.conFondo(puesto, espacio: "Foco", fondo: .mac)
    #expect(cambiado.contains("fondo: mac") && !cambiado.contains("terracota"))
    #expect(EspaciosIsla.conFondo(cambiado, espacio: "Foco", fondo: nil) == base)
    #expect(EspaciosIsla.conFondo(base, espacio: "No existe", fondo: .mac) == base)
    #expect(EspaciosIsla.conFondo(base, espacio: "Trabajo", fondo: nil) == base)
    // En la última sección sin salto final.
    #expect(EspaciosIsla.conFondo("[A]\nfoco: 25", espacio: "A", fondo: .mac) == "[A]\nfoco: 25\nfondo: mac")
}

@Test("Tema por fondo: los fondos claros piden el tema claro")
func luminanciaTema() {
    #expect(LuminanciaFondo.esClaro(LuminanciaFondo.luminancia(r: 1, g: 1, b: 1)))
    #expect(!LuminanciaFondo.esClaro(LuminanciaFondo.luminancia(r: 0.1, g: 0.1, b: 0.2)))
    #expect(!LuminanciaFondo.esClaro(LuminanciaFondo.luminancia(r: 0.5, g: 0.5, b: 0.5)))
    #expect(LuminanciaFondo.esClaro(LuminanciaFondo.luminancia(r: 0.8, g: 0.85, b: 0.9)))
}

// MARK: Clima

private let jsonPronostico = datosJSON("""
{"latitude":4.6,"longitude":-74.1,"timezone":"America/Bogota",
 "current":{"time":"2026-11-16T20:00","temperature_2m":17.6,"apparent_temperature":16.5,"is_day":0,"weather_code":0},
 "daily":{"time":["2026-11-16"],"temperature_2m_max":[19.4],"temperature_2m_min":[9.2]}}
""")

@Test("Clima: se lee la respuesta de Open-Meteo y las cifras se redondean")
func climaAnalizar() {
    let c = ClimaPuro.analizar(jsonPronostico)
    #expect(c == ClimaActual(temperatura: 18, sensacion: 17, codigo: 0, esDia: false, maxima: 19, minima: 9))
}

@Test("Clima: una respuesta rota o incompleta no inventa números")
func climaRoto() {
    #expect(ClimaPuro.analizar(datosJSON("")) == nil)
    #expect(ClimaPuro.analizar(datosJSON("{\"error\":true}")) == nil)
    #expect(ClimaPuro.analizar(datosJSON("{\"current\":{\"temperature_2m\":3}}")) == nil)
    let sinDiario = datosJSON("{\"current\":{\"temperature_2m\":-0.4,\"weather_code\":3}}")
    #expect(ClimaPuro.analizar(sinDiario) == ClimaActual(temperatura: 0, sensacion: 0, codigo: 3, esDia: true))
}

@Test("Clima: la geocodificación devuelve el primer resultado o nada")
func climaGeocodificar() {
    let ok = datosJSON("{\"results\":[{\"name\":\"Bogotá\",\"latitude\":4.60971,\"longitude\":-74.08175,\"country\":\"Colombia\"},{\"name\":\"Otra\",\"latitude\":1,\"longitude\":2}]}")
    #expect(ClimaPuro.analizarGeocodificacion(ok) == LugarClima(nombre: "Bogotá", latitud: 4.60971, longitud: -74.08175))
    #expect(ClimaPuro.analizarGeocodificacion(datosJSON("{\"generationtime_ms\":0.3}")) == nil)
    #expect(ClimaPuro.analizarGeocodificacion(datosJSON("{\"results\":[]}")) == nil)
    #expect(ClimaPuro.analizarGeocodificacion(datosJSON("{\"results\":[{\"name\":\"X\",\"latitude\":99,\"longitude\":0}]}")) == nil)
}

@Test("Clima: la ciudad sale de la zona horaria y las coordenadas se leen con coma")
func climaLugar() {
    #expect(ClimaPuro.ciudad(zonaHoraria: "America/Bogota") == "Bogota")
    #expect(ClimaPuro.ciudad(zonaHoraria: "America/Argentina/Buenos_Aires") == "Buenos Aires")
    #expect(ClimaPuro.ciudad(zonaHoraria: "UTC") == nil)
    #expect(ClimaPuro.ciudad(zonaHoraria: "Etc/UTC") == nil)
    let c = ClimaPuro.coordenadas("4.61, -74.08")
    #expect(c?.latitud == 4.61 && c?.longitud == -74.08)
    #expect(ClimaPuro.coordenadas("4.61") == nil)
    #expect(ClimaPuro.coordenadas("200,1") == nil)
    #expect(ClimaPuro.coordenadas("a,b") == nil)
}

@Test("Clima: las direcciones llevan solo coordenadas o el nombre de la ciudad")
func climaUrls() {
    let p = ClimaPuro.urlPronostico(latitud: 4.61, longitud: -74.08)?.absoluteString ?? ""
    #expect(p.hasPrefix("https://api.open-meteo.com/v1/forecast?"))
    #expect(p.contains("latitude=4.6100") && p.contains("longitude=-74.0800") && p.contains("timezone=auto"))
    let g = ClimaPuro.urlGeocodificacion(ciudad: "Medellín")?.absoluteString ?? ""
    #expect(g.hasPrefix("https://geocoding-api.open-meteo.com/v1/search?") && g.contains("name=Medell%C3%ADn") && g.contains("count=1"))
    #expect(ClimaPuro.urlGeocodificacion(ciudad: "  ") == nil)
}

@Test("Clima: la tabla de códigos tiene texto en español y símbolo de día o noche")
func climaCodigos() {
    #expect(ClimaPuro.descripcion(codigo: 0) == "Despejado")
    #expect(ClimaPuro.descripcion(codigo: 63) == "Lluvia")
    #expect(ClimaPuro.descripcion(codigo: 95) == "Tormenta")
    #expect(ClimaPuro.descripcion(codigo: 1234) == "Variable")
    #expect(ClimaPuro.simbolo(codigo: 0, esDia: true) == "sun.max")
    #expect(ClimaPuro.simbolo(codigo: 0, esDia: false) == "moon.stars")
    #expect(ClimaPuro.simbolo(codigo: 3, esDia: false) == "cloud")
    for c in [0, 1, 2, 3, 45, 48, 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 71, 73, 75, 77, 80, 81, 82, 85, 86, 95, 96, 99] {
        #expect(ClimaPuro.descripcion(codigo: c) != "Variable")
    }
}

@Test("Clima: la frase de dos tonos y la de una línea")
func climaFrase() {
    let c = ClimaActual(temperatura: 18, sensacion: 17, codigo: 0, esDia: false)
    let f = FraseClima.frase(c, lugar: "Bogotá")
    #expect(Frase.texto(f) == "18° ahora en\nBogotá\nse siente 17°\nDespejado")
    #expect(f.first == SegmentoFrase("18°", .dato))
    #expect(f.contains(SegmentoFrase(" ahora en", .enlace)) && f.contains(SegmentoFrase("se siente", .enlace)))
    #expect(FraseClima.unaLinea(c, lugar: "Bogotá") == "18° ahora en Bogotá · se siente 17° · Despejado")
    let igual = ClimaActual(temperatura: 18, sensacion: 18, codigo: 3, esDia: true)
    #expect(FraseClima.unaLinea(igual, lugar: "Quito") == "18° ahora en Quito · Nublado")
    #expect(Frase.texto(FraseClima.frase(igual, lugar: "Quito")) == "18° ahora en\nQuito\nNublado")
}

@Test("Clima: sin datos la frase es la fecha de hoy")
func climaFecha() {
    #expect(Frase.texto(FraseClima.sinDatos(f(16, 9), calendario: calendarioDePrueba())) == "Hoy es\nlunes\n16 de noviembre")
}

@Test("Clima: se pide como mucho cada 30 minutos, a los 10 si falló, y un dato de más de 3 horas ya no vale")
func climaPolitica() {
    let t0 = f(16, 9)
    #expect(PoliticaClima.debeActualizar(ultimoIntento: nil, fallo: false, ahora: t0))
    #expect(!PoliticaClima.debeActualizar(ultimoIntento: t0, fallo: false, ahora: t0.addingTimeInterval(29 * 60)))
    #expect(PoliticaClima.debeActualizar(ultimoIntento: t0, fallo: false, ahora: t0.addingTimeInterval(30 * 60)))
    #expect(!PoliticaClima.debeActualizar(ultimoIntento: t0, fallo: true, ahora: t0.addingTimeInterval(9 * 60)))
    #expect(PoliticaClima.debeActualizar(ultimoIntento: t0, fallo: true, ahora: t0.addingTimeInterval(10 * 60)))
    #expect(PoliticaClima.debeActualizar(ultimoIntento: t0, fallo: false, ahora: t0.addingTimeInterval(-5)))   // el reloj retrocedió
    #expect(PoliticaClima.vigente(ultimoExito: t0, ahora: t0.addingTimeInterval(2 * 3600)))
    #expect(!PoliticaClima.vigente(ultimoExito: t0, ahora: t0.addingTimeInterval(3 * 3600 + 1)))
    #expect(!PoliticaClima.vigente(ultimoExito: nil, ahora: t0))
}

// MARK: Esquina

@Test("Esquina: el ajuste se lee y sin él (o con algo raro) es la inferior derecha")
func esquinaAjuste() {
    #expect(EsquinaLanzador(ajuste: nil) == .inferiorDerecha)
    #expect(EsquinaLanzador(ajuste: "ninguna") == .ninguna)
    #expect(EsquinaLanzador(ajuste: "superiorIzquierda") == .superiorIzquierda)
    #expect(EsquinaLanzador(ajuste: "Inferior Izquierda") == .inferiorIzquierda)
    #expect(EsquinaLanzador(ajuste: "otra cosa") == .inferiorDerecha)
}

@Test("Esquina: el cuadrito queda en la esquina elegida (y ninguna no tiene)")
func esquinaMarco() {
    func m(_ e: EsquinaLanzador) -> MarcoEsquina? { e.marco(x: 100, y: 50, ancho: 1000, alto: 800, lado: 4) }
    #expect(m(.inferiorDerecha) == MarcoEsquina(x: 1096, y: 50, lado: 4))
    #expect(m(.inferiorIzquierda) == MarcoEsquina(x: 100, y: 50, lado: 4))
    #expect(m(.superiorDerecha) == MarcoEsquina(x: 1096, y: 846, lado: 4))
    #expect(m(.superiorIzquierda) == MarcoEsquina(x: 100, y: 846, lado: 4))
    #expect(m(.ninguna) == nil)
}

@Test("Esquina: se queda 0,3 s y dispara una sola vez hasta que el puntero sale")
func esquinaEspera() {
    var p = PoliticaEsquina()
    let r1 = p.entra(botonesAbajo: false)
    #expect(r1)
    let r2 = p.vence(botonesAbajo: false, punteroDentro: true)
    #expect(r2)
    let r3 = p.entra(botonesAbajo: false)
    #expect(!r3)                      // sigue dentro: no vuelve a programar
    let r4 = p.vence(botonesAbajo: false, punteroDentro: true)
    #expect(!r4)  // ni a disparar
    p.sale()
    let r5 = p.entra(botonesAbajo: false)
    #expect(r5)
    let r6 = p.vence(botonesAbajo: false, punteroDentro: true)
    #expect(r6)
}

@Test("Esquina: no dispara si salió antes, en un arrastre ni si apretó un botón mientras esperaba")
func esquinaArrastre() {
    var p = PoliticaEsquina()
    let r7 = p.entra(botonesAbajo: false)
    #expect(r7)
    p.sale()
    let r8 = p.vence(botonesAbajo: false, punteroDentro: true)
    #expect(!r8)   // el cronómetro viejo no hace nada

    var q = PoliticaEsquina()
    let r9 = q.entra(botonesAbajo: true)
    #expect(!r9)                          // entró arrastrando
    let r10 = q.vence(botonesAbajo: false, punteroDentro: true)
    #expect(!r10)
    let r11 = q.entra(botonesAbajo: false)
    #expect(!r11)                         // soltar dentro de la esquina no la activa
    q.sale()
    let r12 = q.entra(botonesAbajo: false)
    #expect(r12)

    var r = PoliticaEsquina()
    let r13 = r.entra(botonesAbajo: false)
    #expect(r13)
    let r14 = r.vence(botonesAbajo: true, punteroDentro: true)
    #expect(!r14)     // apretó un botón en medio
    #expect(r.fase == .bloqueada)

    var s = PoliticaEsquina()
    let r15 = s.entra(botonesAbajo: false)
    #expect(r15)
    let r16 = s.vence(botonesAbajo: false, punteroDentro: false)
    #expect(!r16)   // ya no está encima
}

// MARK: Dock del sistema

private final class SistemaFalso: AjustesDockSistema {
    var valor: AjusteDockSistema
    var escrituras: [AjusteDockSistema] = []
    var reinicios = 0
    init(_ v: AjusteDockSistema) { valor = v }
    func leer() -> AjusteDockSistema { valor }
    func escribir(_ a: AjusteDockSistema) { valor = a; escrituras.append(a) }
    func reiniciarDock() { reinicios += 1 }
}

private final class AlmacenFalso: AlmacenDockSistema {
    var interruptor = false
    var previo: AjusteDockSistema?
}

private let conRetardoCorto = AjusteDockSistema(autohide: true, retardo: 0.5)
private let sinNada = AjusteDockSistema.defecto

@Test("Dock del sistema: el texto guardado conserva la clave ausente y se rechaza lo roto")
func dockSistemaTexto() {
    for a in [sinNada, conRetardoCorto, AjusteDockSistema(autohide: false, retardo: nil), AjusteDockSistema(autohide: nil, retardo: 0.25)] {
        #expect(AjusteDockSistema(texto: a.texto) == a)
    }
    #expect(AjusteDockSistema(texto: "autohide=-;retardo=-") == sinNada)
    #expect(AjusteDockSistema(texto: "basura") == nil)
    #expect(AjusteDockSistema(texto: "autohide=quizá;retardo=-") == nil)
    #expect(AjusteDockSistema(texto: "autohide=true") == nil)
}

@Test("Dock del sistema: oculto es autohide con retardo larguísimo")
func dockSistemaOculto() {
    #expect(AjusteDockSistema.ocultoPorLaApp.estaOculto)
    #expect(AjusteDockSistema(autohide: true, retardo: 100).estaOculto)
    #expect(!conRetardoCorto.estaOculto)
    #expect(!AjusteDockSistema(autohide: true, retardo: nil).estaOculto)
    #expect(!AjusteDockSistema(autohide: false, retardo: 1000).estaOculto)
    #expect(!sinNada.estaOculto)
}

@Test("Dock del sistema: encender guarda lo de antes, escribe y reinicia; apagar lo devuelve exacto")
func dockSistemaCiclo() {
    let s = SistemaFalso(conRetardoCorto), a = AlmacenFalso()
    let c = ControlDockSistema(sistema: s, almacen: a)
    #expect(c.encender() == .cambiado)
    #expect(a.previo == conRetardoCorto && a.interruptor)
    #expect(s.valor == .ocultoPorLaApp && s.reinicios == 1)
    #expect(c.restaurar() == .cambiado)
    #expect(s.valor == conRetardoCorto && s.reinicios == 2)
    #expect(a.previo == nil && !a.interruptor)
}

@Test("Dock del sistema: las claves ausentes se borran al restaurar, no se escriben con un valor")
func dockSistemaClavesAusentes() {
    let s = SistemaFalso(sinNada), a = AlmacenFalso()
    let c = ControlDockSistema(sistema: s, almacen: a)
    c.encender()
    #expect(a.previo == sinNada)
    c.restaurar()
    #expect(s.valor == sinNada && s.valor.autohide == nil && s.valor.retardo == nil)
}

@Test("Dock del sistema: encender dos veces no pisa lo guardado ni reinicia de más")
func dockSistemaIdempotente() {
    let s = SistemaFalso(conRetardoCorto), a = AlmacenFalso()
    let c = ControlDockSistema(sistema: s, almacen: a)
    c.encender()
    #expect(c.encender() == .nada)
    #expect(a.previo == conRetardoCorto)
    #expect(s.reinicios == 1 && s.escrituras.count == 1)
    c.restaurar()
    #expect(c.restaurar() == .nada)
    #expect(s.reinicios == 2)
    #expect(s.valor == conRetardoCorto)
}

@Test("Dock del sistema: restaurar sin nada guardado solo toca el Dock si está oculto como lo deja la app")
func dockSistemaSinGuardado() {
    let visible = SistemaFalso(AjusteDockSistema(autohide: false, retardo: nil)), a1 = AlmacenFalso()
    #expect(ControlDockSistema(sistema: visible, almacen: a1).restaurar() == .nada)
    #expect(visible.escrituras.isEmpty && visible.reinicios == 0)

    let oculto = SistemaFalso(.ocultoPorLaApp), a2 = AlmacenFalso()
    #expect(ControlDockSistema(sistema: oculto, almacen: a2).restaurar() == .cambiado)
    #expect(oculto.valor == sinNada && oculto.reinicios == 1)
}

@Test("Dock del sistema: un interruptor viejo con lo guardado sucio no impide guardar lo de ahora")
func dockSistemaPrevioViejo() {
    let s = SistemaFalso(conRetardoCorto), a = AlmacenFalso()
    a.previo = AjusteDockSistema(autohide: false, retardo: 3)   // de otra vez; el interruptor está apagado
    ControlDockSistema(sistema: s, almacen: a).encender()
    #expect(a.previo == conRetardoCorto)
}

@Test("Dock del sistema: al arrancar con el Dock ya oculto a mano se adopta como encendido y 'antes' es de fábrica")
func dockSistemaAdoptar() {
    let s = SistemaFalso(AjusteDockSistema(autohide: true, retardo: 1000)), a = AlmacenFalso()
    let c = ControlDockSistema(sistema: s, almacen: a)
    #expect(c.alArrancar() == .adoptado)
    #expect(a.interruptor && a.previo == sinNada)
    #expect(s.escrituras.isEmpty && s.reinicios == 0)
    #expect(c.restaurar() == .cambiado)           // apagarlo devuelve el Dock del sistema
    #expect(s.valor == sinNada)
    #expect(c.alArrancar() == .nada)
}

@Test("Dock del sistema: al arrancar, con lo guardado y oculto no cambia nada; encendido pero visible, lo vuelve a ocultar")
func dockSistemaArranque() {
    let s = SistemaFalso(.ocultoPorLaApp), a = AlmacenFalso()
    a.previo = conRetardoCorto
    let c = ControlDockSistema(sistema: s, almacen: a)
    #expect(c.alArrancar() == .nada)
    #expect(a.interruptor && a.previo == conRetardoCorto)

    let v = SistemaFalso(sinNada), b = AlmacenFalso()
    b.interruptor = true
    b.previo = conRetardoCorto
    #expect(ControlDockSistema(sistema: v, almacen: b).alArrancar() == .cambiado)
    #expect(v.valor == .ocultoPorLaApp && b.previo == sinNada)

    let n = SistemaFalso(sinNada), c0 = AlmacenFalso()
    #expect(ControlDockSistema(sistema: n, almacen: c0).alArrancar() == .nada)
    #expect(n.escrituras.isEmpty)
}

// MARK: Dock: el lanzador y el clima

@Test("Dock: las piezas lanzador y clima se leen en la línea dock: y están en el Dock de siempre")
func dockPiezasNuevas() {
    #expect(ReglasDock.analizar("lanzador, clima, reloj", home: "/h") == [.lanzador, .clima, .reloj])
    #expect(ReglasDock.analizar("tiempo, apps", home: "/h") == [.clima, .lanzador])
    let p = ReglasDock.porOmision(masUsadas: [], home: "/h")
    #expect(p.first == .lanzador && p.contains(.clima))
}

@Test("Dock: con poco ancho el clima se suelta antes que el reloj y el lanzador es lo último que se va")
func dockSoltarClima() {
    let todo: [PiezaDock] = [.lanzador, .reloj, .clima, .papelera]
    let ancho = MedidasDock.anchoBarra(ReglasDock.colocar(todo, anchoDisponible: 10_000).piezas)
    #expect(ReglasDock.colocar(todo, anchoDisponible: ancho).soltadas.isEmpty)
    let r = ReglasDock.colocar(todo, anchoDisponible: ancho - 1)
    #expect(r.soltadas == [.clima])
}

@Test("Dock: con el lanzador abierto la barra se muestra y se queda; al cerrarse vuelve a la política")
func dockRetener() {
    var p = PoliticaDock(modo: .alTocarBorde)
    let r17 = p.retener(true)
    #expect(r17 == .mostrar)
    #expect(p.visible)
    #expect(p.venceOcultar() == .ninguna)                     // retenida: no se oculta sola
    let r18 = p.retener(true)
    #expect(r18 == .ninguna)
    let r19 = p.retener(false)
    #expect(r19 == .programarOcultar(PoliticaDock.esperaOcultar))
    #expect(p.venceOcultar() == .ocultar)

    var q = PoliticaDock(modo: .alTocarBorde)
    _ = q.bordeSostenido()
    let r20 = q.retener(true)
    #expect(r20 == .cancelarOcultar)

    var s = PoliticaDock(modo: .siempre)
    #expect(s.alternarAtajo() == .ocultar)                    // la escondió el atajo
    let r21 = s.retener(true)
    #expect(r21 == .mostrar)
    let r22 = s.retener(false)
    #expect(r22 == .ocultar)                     // vuelve a lo que decía el atajo
    var t = PoliticaDock(modo: .siempre)
    let r23 = t.retener(true)
    #expect(r23 == .cancelarOcultar)
    let r24 = t.retener(false)
    #expect(r24 == .ninguna)
}

@Test("Fijas: fijar agrega al final y quitar la saca; el resto no se toca")
func fijasAlternar() {
    #expect(MasUsadas.alternarFija(["a"], id: "b") == ["a", "b"])
    #expect(MasUsadas.alternarFija(["a", "b", "c"], id: "b") == ["a", "c"])
    #expect(MasUsadas.alternarFija([], id: "x") == ["x"])
}
