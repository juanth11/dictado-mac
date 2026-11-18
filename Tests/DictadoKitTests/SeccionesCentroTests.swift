import Testing
@testable import DictadoKit

// Consumo, Herramientas, Automatizaciones, Finanzas y Noticias del Centro: la lectura del JSON (tolerante) y las cuentas de cada sección.

private func dia(_ n: Int, mensajes: Int = 1, tokens: Int = 0, costo: Double) -> DiaConsumo {
    DiaConsumo(dia: "2026-11-\(String(format: "%02d", n))", cifras: CifrasConsumo(mensajes: mensajes, tokens: tokens, costoUSD: costo))
}

private let consumoEjemplo = """
{"version": 1, "generado": "2026-11-16T14:48:00-05:00", "estado": "ok", "campo_nuevo": 1, "pricing_version": "2026-11-16", "completo": false, "pendientes": 3,
 "claude_code": {"disponible": true, "primer_dia": "2026-10-18", "incluye_subagentes": true, "fuente": "~/.claude/projects (solo lectura)",
   "dias": [{"dia": "2026-11-15", "mensajes": 3, "entrada": 10, "salida": 20, "cache_lectura": 100, "cache_escritura": 5, "tokens": 135, "costo_usd": 1.5, "costo_incompleto": false},
            {"dia": "2026-11-16", "mensajes": 2, "tokens": 50, "costo_usd": 0.5, "costo_incompleto": true}, {"sin": "dia"}],
   "modelos": [{"modelo": "Opus 5.5", "mensajes": 5, "tokens": 185, "costo_usd": 2.0, "costo_incompleto": false}, {"mensajes": 1}],
   "proyectos": [{"proyecto": "dictado", "mensajes": 5, "tokens": 185, "costo_usd": 2.0}],
   "totales": {"hoy": {"mensajes": 2, "tokens": 50, "costo_usd": 0.5, "costo_incompleto": true}, "ayer": null,
               "siete_dias": {"mensajes": 5, "tokens": 185, "costo_usd": 2.0}, "treinta_dias": {"mensajes": 5, "tokens": 185, "costo_usd": 2.0}}},
 "hermes": {"disponible": false, "primer_dia": null, "dias": [], "modelos": [], "proyectos": [], "motivo": "el VPS no respondió y no hay una lectura anterior",
            "leido": null, "desactualizado": true, "totales": {"hoy": {}, "ayer": null, "siete_dias": {}, "treinta_dias": {}}}}
"""

@Test("Consumo: se lee el JSON, se saltan filas rotas y se conserva el motivo de lo que no hay")
func consumoDecodificar() {
    let c = ConsumoCentro.decodificar(datosJSON(consumoEjemplo))
    #expect(c?.version == 1 && c?.completo == false && c?.pendientes == 3 && c?.pricingVersion == "2026-11-16")
    let cc = c?.claudeCode
    #expect(cc?.disponible == true && cc?.incluyeSubagentes == true && cc?.primerDia == "2026-10-18")
    #expect(cc?.dias.map(\.dia) == ["2026-11-15", "2026-11-16"])
    #expect(cc?.dias.first?.cifras.tokens == 135 && cc?.dias.first?.cifras.costoUSD == 1.5)
    #expect(cc?.dias.last?.cifras.costoIncompleto == true)
    #expect(cc?.modelos.map(\.nombre) == ["Opus 5.5"] && cc?.proyectos.map(\.nombre) == ["dictado"])
    #expect(cc?.hoy.costoIncompleto == true && cc?.ayer == nil && cc?.treintaDias.mensajes == 5)
    #expect(c?.hermes.disponible == false && c?.hermes.desactualizado == true)
    #expect(c?.hermes.motivo == "el VPS no respondió y no hay una lectura anterior")
    // Lo que no es un objeto con las dos fuentes no es un consumo.
    #expect(ConsumoCentro.decodificar(datosJSON("{\"ok\": false, \"error\": \"x\"}")) == nil)
    #expect(ConsumoCentro.decodificar(datosJSON("[]")) == nil)
    #expect(ConsumoCentro.decodificar(datosJSON("{\"version\": 1}")) == nil)
}

@Test("Consumo: las barras son fracciones del día más alto y un día sin datos queda en cero")
func consumoBarras() {
    let dias = [dia(1, mensajes: 0, costo: 0), dia(2, costo: 10), dia(3, costo: 5), dia(4, costo: 0.01)]
    let f = ConsumoCentro.fracciones(dias, por: .costo)
    #expect(f[0] == 0 && f[1] == 1 && f[2] == 0.5)
    #expect(f[3] == 0.03)                       // lo mínimo para que se vea
    #expect(ConsumoCentro.fracciones([dia(1, mensajes: 0, costo: 0)], por: .costo) == [0])
    #expect(ConsumoCentro.diaMasAlto(dias, por: .costo)?.dia == "2026-11-02")
    #expect(ConsumoCentro.diaMasAlto([dia(1, mensajes: 0, costo: 0)], por: .costo) == nil)
}

@Test("Consumo: el reparto suma uno, la variación semanal exige dos semanas y el promedio ignora los días vacíos")
func consumoCuentas() {
    let items = [ItemConsumo(nombre: "A", cifras: CifrasConsumo(costoUSD: 75)), ItemConsumo(nombre: "B", cifras: CifrasConsumo(costoUSD: 25))]
    let r = ConsumoCentro.reparto(items, por: .costo)
    #expect(r.map(\.fraccion) == [0.75, 0.25])
    #expect(ConsumoCentro.reparto([ItemConsumo(nombre: "A", cifras: CifrasConsumo())], por: .costo).isEmpty)

    let semanaPasada = (1...7).map { dia($0, costo: 10) }
    let estaSemana = (8...14).map { dia($0, costo: 15) }
    #expect(ConsumoCentro.variacionSemanal(semanaPasada + estaSemana, por: .costo) == 0.5)
    #expect(ConsumoCentro.variacionSemanal(estaSemana, por: .costo) == nil)                      // faltan días
    #expect(ConsumoCentro.variacionSemanal((1...7).map { dia($0, mensajes: 0, costo: 0) } + estaSemana, por: .costo) == nil)   // la previa fue cero
    #expect(ConsumoCentro.textoVariacion(0.5) == "+50 %" && ConsumoCentro.textoVariacion(-0.08) == "−8 %" && ConsumoCentro.textoVariacion(0.001) == "igual")

    let con = [dia(1, mensajes: 0, costo: 0), dia(2, costo: 10), dia(3, costo: 20)]
    #expect(ConsumoCentro.promedioDiario(con, ultimos: 7, por: .costo) == 15)
    #expect(ConsumoCentro.promedioDiario([dia(1, mensajes: 0, costo: 0)], por: .costo) == nil)
    #expect(ConsumoCentro.textoCosto(CifrasConsumo(costoUSD: 1234.5)) == "US$ 1.234,50")
    #expect(ConsumoCentro.textoCosto(CifrasConsumo(costoUSD: 3, costoIncompleto: true)) == "US$ 3,00+")
    #expect(ConsumoCentro.etiqueta(dia: "2026-11-16", calendario: calendarioDePrueba()) == "lun 16")
}

@Test("Consumo: agrupar deja a lo más N filas y junta el resto (y un 'Otros' previo) en una sola")
func consumoAgrupar() {
    func item(_ n: String, _ usd: Double) -> ItemConsumo { ItemConsumo(nombre: n, cifras: CifrasConsumo(mensajes: 1, tokens: 10, costoUSD: usd)) }
    let todos = [item("a", 5), item("b", 4), item("c", 3), item("d", 2), item("e", 1), item("Otros", 10)]
    let g = ConsumoCentro.agrupar(todos, maximo: 4)
    #expect(g.map(\.nombre) == ["a", "b", "c", "Otros"])
    #expect(g.last?.cifras.costoUSD == 13 && g.last?.cifras.tokens == 30 && g.last?.cifras.mensajes == 3)
    #expect(ConsumoCentro.agrupar(Array(todos.prefix(3)), maximo: 4).map(\.nombre) == ["a", "b", "c"])
    #expect(ConsumoCentro.agrupar(todos, maximo: 6).count == 6)
    let suma = g.reduce(0) { $0 + $1.cifras.costoUSD }
    #expect(suma == todos.reduce(0) { $0 + $1.cifras.costoUSD })          // no se pierde ni se inventa nada
}

private let herramientasEjemplo = """
{"version": 1, "generado": "2026-11-16T14:00:00-05:00", "uso_desde": "2026-10-15",
 "mcp": {"servidores": [
   {"nombre": "firecrawl", "alcance": "usuario", "activo": true, "tipo": "http", "destino": "mcp.firecrawl.dev", "pide_autorizar": false,
    "usos_7": 20, "usos_30": 73, "ultimo_uso": "2026-11-16T10:00:00-05:00", "herramientas": [{"nombre": "scrape", "usos": 50}, {"nombre": "search", "usos": 23}]},
   {"nombre": "drawio", "alcance": "usuario", "activo": true, "tipo": "stdio", "destino": "npx", "usos_7": 0, "usos_30": 0},
   {"nombre": "context7", "alcance": "usuario", "activo": false, "tipo": "http", "destino": "mcp.context7.com", "usos_7": 0, "usos_30": 0}, {"sin": "nombre"}],
  "integrados": [{"nombre": "ccd_turn", "alcance": "integrado", "activo": true, "usos_7": 5, "usos_30": 9}]},
 "skills": {"items": [{"nombre": "design-loop", "origen": "usuario", "descripcion": "Bucle", "activa": true, "usos_7": 0, "usos_30": 7, "ultimo_uso": "2026-11-12T10:00:00-05:00"},
                      {"nombre": "ffmpeg", "origen": "usuario", "activa": true, "usos_7": 0, "usos_30": 0},
                      {"nombre": "vieja", "origen": "usuario", "activa": false, "usos_7": 0, "usos_30": 0}], "en_reserva": 168},
 "plugins": [{"nombre": "egm", "origen": "egm", "version": "0.1.0", "activo": true}],
 "hermes": {"mcp": [{"nombre": "crawl4ai", "activo": true, "usos_30": 5}], "skills_total": 76, "herramientas": [{"nombre": "terminal", "usos": 195}], "leido": "2026-11-16T13:32:44-05:00"}}
"""

@Test("Herramientas: se lee el inventario y lo activo sin uso se destaca; lo apagado no cuenta como olvidado")
func herramientasLectura() {
    let h = HerramientasCentro.decodificar(datosJSON(herramientasEjemplo))
    #expect(h?.usoDesde == "2026-10-15" && h?.skillsEnReserva == 168)
    #expect(h?.servidores.map(\.nombre) == ["firecrawl", "drawio", "context7"])
    #expect(h?.servidores.first?.uso.usos30 == 73 && h?.servidores.first?.uso.herramientas.first?.nombre == "scrape")
    #expect(h?.integrados.first?.integrado == true)
    #expect(h?.plugins.first?.version == "0.1.0")
    #expect(h?.hermes?.skillsTotal == 76 && h?.hermes?.mcp.first?.usos30 == 5)
    guard let h else { return }
    #expect(HerramientasCentro.sinUso(h.servidores).map(\.nombre) == ["drawio"])        // context7 está apagado: no es un olvido
    #expect(HerramientasCentro.sinUso(h.skills).map(\.nombre) == ["ffmpeg"])
    #expect(HerramientasCentro.filtrar(h.skills, .usadas).map(\.nombre) == ["design-loop"])
    #expect(HerramientasCentro.filtrar(h.skills, .todo).count == 3)
    #expect(HerramientasCentro.conexion(h.servidores[0]) == "http · mcp.firecrawl.dev")
    #expect(HerramientasCentro.decodificar(datosJSON("{\"version\": 1}")) == nil)
}

@Test("Herramientas: la barra de uso y el último uso")
func herramientasBarras() {
    #expect(HerramientasCentro.fraccionUso(50, mayor: 100) == 0.5)
    #expect(HerramientasCentro.fraccionUso(0, mayor: 100) == 0)
    #expect(HerramientasCentro.fraccionUso(1, mayor: 1000) == 0.03)
    #expect(HerramientasCentro.fraccionUso(5, mayor: 0) == 0)
    #expect(HerramientasCentro.ultimoUso(UsoHerramienta(), ahora: f(16, 14)) == "sin uso")
    #expect(HerramientasCentro.ultimoUso(UsoHerramienta(usos30: 1, ultimoUso: f(13, 10)), ahora: f(16, 14)) == "hace 3 d")
}

private let automatizacionesEjemplo = """
{"version": 1, "generado": "2026-11-16T14:48:00-05:00", "estado": "ok",
 "resumen": {"total": 4, "fallo": 1, "parado": 1, "atrasado": 0, "al_dia": 1, "sin_dato": 0, "apagado": 1},
 "fuentes": [{"id": "crontab", "nombre": "Mac · crontab", "total": 0, "nota": "sin entradas en el crontab"}],
 "vps": {"leido": "2026-11-16T14:40:00-05:00", "desactualizado": false, "error": null},
 "items": [
  {"id": "hermes:1", "origen": "hermes", "nombre": "regulatory-scan", "que_hace": "Trabajo de Hermes", "horario": "lun a las 11:00", "activo": true,
   "ultima": "2026-11-16T11:00:00-05:00", "proxima": "2026-11-23T11:00:00-05:00", "resultado": "error", "detalle": "RuntimeError: 401", "estado": "fallo", "propio": true},
  {"id": "claude:ritual", "origen": "claude", "nombre": "ritual-diario-cerebro", "horario": "lun a vie a las 4:45", "activo": true, "ultima": "2026-07-23T12:24:00-05:00",
   "estado": "parado", "parado_desde": "2026-07-23T12:24:00-05:00", "dias_parado": 116},
  {"id": "hermes:2", "origen": "hermes", "nombre": "centro-brief", "horario": "todos los días a las 5:30", "estado": "al_dia", "ultima": "2026-11-16T05:30:00-05:00", "resultado": "ok"},
  {"id": "hermes:3", "origen": "hermes", "nombre": "health-check", "activo": false, "estado": "apagado", "parado_desde": "2026-05-11T11:30:00-05:00", "dias_parado": 189},
  {"id": "x", "nombre": "estado raro", "estado": "algo-nuevo"}, {"sin": "id"}]}
"""

@Test("Automatizaciones: se lee lo programado, un estado desconocido es 'sin dato' y la frase cuenta lo que pide atención")
func automatizacionesLectura() {
    let a = AutomatizacionesCentro.decodificar(datosJSON(automatizacionesEjemplo))
    #expect(a?.items.map(\.nombre) == ["regulatory-scan", "ritual-diario-cerebro", "centro-brief", "health-check", "estado raro"])
    #expect(a?.items.last?.estado == .sinDato)
    #expect(a?.items.first?.estado == .fallo && a?.items.first?.detalle == "RuntimeError: 401")
    #expect(a?.resumen.pidenAtencion == 2)
    #expect(a?.fuentes.first?.nota == "sin entradas en el crontab")
    #expect(a?.vpsLeido != nil && a?.vpsDesactualizado == false)
    guard let a else { return }
    let g = AutomatizacionesCentro.grupos(a.items)
    #expect(g.atencion.map(\.nombre) == ["regulatory-scan", "ritual-diario-cerebro"])
    #expect(g.apagados.map(\.nombre) == ["health-check"])
    #expect(g.activos.map(\.nombre) == ["centro-brief", "estado raro"])
    #expect(AutomatizacionesCentro.frase(a.resumen) == "2 piden atención · 1 al día · 1 apagado")
    #expect(AutomatizacionesCentro.frase(ResumenAutomatizaciones()) == "Nada programado")
    #expect(AutomatizacionesCentro.decodificar(datosJSON("{\"version\": 1}")) == nil)
}

@Test("Automatizaciones: 'parado desde' y los momentos se dicen en palabras")
func automatizacionesTextos() {
    let cal = calendarioDePrueba()
    let ahora = f(16, 14, 48)
    let parado = ItemAutomatizacion(id: "a", origen: "claude", nombre: "n", estado: .parado, paradoDesde: fe(2026, 7, 23, 12), diasParado: 116)
    #expect(AutomatizacionesCentro.textoParado(parado, ahora: ahora, calendario: cal) == "Parado desde el 23 jul · hace 116 días")
    let atrasado = ItemAutomatizacion(id: "b", origen: "launchagent", nombre: "n", estado: .atrasado, paradoDesde: f(15, 5, 33), diasParado: 1)
    #expect(AutomatizacionesCentro.textoParado(atrasado, ahora: ahora, calendario: cal) == "Se saltó una corrida · la última fue el 15 nov")
    #expect(AutomatizacionesCentro.textoParado(ItemAutomatizacion(id: "c", origen: "x", nombre: "n", estado: .alDia), ahora: ahora, calendario: cal) == nil)
    #expect(AutomatizacionesCentro.textoMomento(f(16, 5, 30), ahora: ahora, calendario: cal) == "hoy 05:30")
    #expect(AutomatizacionesCentro.textoMomento(f(15, 20, 30), ahora: ahora, calendario: cal) == "ayer 20:30")
    #expect(AutomatizacionesCentro.textoMomento(f(17, 7), ahora: ahora, calendario: cal) == "mañana 07:00")
    #expect(AutomatizacionesCentro.textoMomento(f(1, 7), ahora: ahora, calendario: cal) == "1 nov 07:00")
    #expect(AutomatizacionesCentro.textoMomento(nil, ahora: ahora, calendario: cal) == "sin dato")
    #expect(AutomatizacionesCentro.lugar("vps-cron") == "VPS · cron")
}

private let finanzasEjemplo = """
{"version": 1, "disponible": true,
 "resumen": {"actualizado": "2026-11-15", "dias_sin_actualizar": 1, "patrimonio": 116994432, "delta": 24101432, "liquidez": 37578048, "neto_mes": 447892,
             "colchon": 10613295, "colchon_piso": 21000000, "colchon_meta": 27000000, "alertas": ["Pagos vencidos: Agua"], "enlace": "ruta/index.html"},
 "flujo": {"ingreso_mes": 2750000, "egreso_mes": 2302108, "neto_mes": 447892, "runway": null},
 "historico": [{"mes": "2026-06", "ingreso": 4788000, "egreso": 4048000, "neto": 740000}, {"mes": "2026-07", "ingreso": 1930000, "egreso": 1577270}, {"mes": "2026-08", "ingreso": null, "egreso": null}],
 "pagos": [{"concepto": "Cuota", "monto": 572436, "vence": "2026-11-23", "dias": 8, "critico": true}, {"concepto": "sin monto"}],
 "proyeccion_personal": {"disponible": false, "fuente": {"fecha": "2026-07-06", "dias": 133}, "caja_cop": null, "burn_mes_cop": null, "runway_meses": null, "escenarios": null},
 "orbita": {"disponible": true, "fuente": {"fecha": "2026-07-06", "dias": 133}, "mrr_cop": 1500000}}
"""

@Test("Finanzas: se lee el ledger, los meses sin datos y los pagos sin monto se saltan, y lo que no existe queda nil")
func finanzasLectura() {
    let fi = FinanzasCentro.decodificar(datosJSON(finanzasEjemplo))
    #expect(fi?.disponible == true && fi?.diasSinActualizar == 1 && fi?.patrimonio == 116994432 && fi?.colchonMeta == 27000000)
    #expect(fi?.historico.map(\.mes) == ["2026-06", "2026-07"])
    #expect(fi?.historico.last?.neto == 352730)           // sin `neto`, ingreso menos egreso
    #expect(fi?.pagos.map(\.concepto) == ["Cuota"] && fi?.pagos.first?.critico == true)
    #expect(fi?.proyeccionDisponible == false && fi?.caja == nil && fi?.burn == nil && fi?.runwayMeses == nil)
    #expect(fi?.proyeccionFuente?.dias == 133 && fi?.orbitaDisponible == true && fi?.mrr == 1500000)
    #expect(fi?.alertas == ["Pagos vencidos: Agua"])
    // Sin el ledger, nada se inventa.
    let sin = FinanzasCentro.decodificar(datosJSON("{\"version\": 1, \"disponible\": false, \"resumen\": null, \"historico\": [], \"pagos\": []}"))
    #expect(sin?.disponible == false && sin?.patrimonio == nil && sin?.colchon == nil)
    #expect(FinanzasCentro.decodificar(datosJSON("{\"version\": 1}")) == nil)
}

@Test("Finanzas: los pesos se dicen en millones o miles, la edad de la fuente es honesta y la regla del colchón se acota")
func finanzasFormato() {
    #expect(FinanzasCentro.pesos(116_994_432) == "$ 117 M" && FinanzasCentro.pesos(10_613_295) == "$ 10,6 M")
    #expect(FinanzasCentro.pesos(572_436) == "$ 572 k" && FinanzasCentro.pesos(-1_500_000) == "−$ 1,5 M" && FinanzasCentro.pesos(850) == "$ 850")
    #expect(FinanzasCentro.pesosCompletos(572_436) == "$ 572.436" && FinanzasCentro.pesosCompletos(-1450000) == "−$ 1.450.000")
    let cal = calendarioDePrueba()
    #expect(FinanzasCentro.edad(FuenteFechada(fecha: nil, dias: 0)) == "de hoy" && FinanzasCentro.edad(FuenteFechada(fecha: nil, dias: 1)) == "de ayer")
    #expect(FinanzasCentro.edad(FuenteFechada(fecha: fe(2026, 7, 6), dias: 133), calendario: cal) == "de hace 133 días (6 jul)")
    #expect(Frescura.de(dias: 1) == .vigente && Frescura.de(dias: 10) == .vieja && Frescura.de(dias: 133) == .muyVieja)
    let r = FinanzasCentro.regla(actual: 10_613_295, piso: 21_000_000, meta: 27_000_000)
    #expect(r != nil && abs((r?.actual ?? 0) - 0.393) < 0.001 && abs((r?.piso ?? 0) - 0.778) < 0.001)
    #expect(FinanzasCentro.regla(actual: 40, piso: nil, meta: 30)?.actual == 1)
    #expect(FinanzasCentro.regla(actual: 5, piso: nil, meta: nil) == nil)
    #expect(FinanzasCentro.nombreMes("2026-11") == "nov" && FinanzasCentro.nombreMes("raro") == "raro")
}

@Test("Noticias: agrupa por vertical, solo abre enlaces web y dice la hora si el radar la trae")
func noticiasLectura() {
    let json = """
    {"version": 1, "disponible": true, "origen": "VPS (brief de las 5:00)", "generado": "2026-11-16T05:00:24-05:00", "dias_sin_actualizar": 0, "total": 3,
     "verticales": [{"vertical": "Lumina", "items": [
        {"id": "1", "titulo": "Nueva UVT", "fuente": "Revista Semana", "fecha": "10 nov", "por_que": "Cambia tu cálculo.", "url": "https://x.co/a"},
        {"id": "2", "titulo": "Con hora", "fuente": "DIAN", "fecha": "13 nov", "publicada": "2026-11-13T09:05:00-05:00", "url": "javascript:alert(1)"}, {"titulo": ""}]},
       {"vertical": "Vacía", "items": []}]}
    """
    let n = NoticiasCentro.decodificar(datosJSON(json))
    #expect(n?.disponible == true && n?.total == 2 && n?.verticales.map(\.vertical) == ["Lumina"])
    #expect(n?.verticales.first?.items[0].url?.host == "x.co" && n?.verticales.first?.items[1].url == nil)
    guard let items = n?.verticales.first?.items else { return }
    #expect(NoticiasCentro.cuando(items[0]) == "10 nov")
    #expect(NoticiasCentro.cuando(items[1], calendario: calendarioDePrueba()) == "13 nov · 09:05")
    let vacio = NoticiasCentro.decodificar(datosJSON("{\"version\": 1, \"disponible\": false, \"verticales\": [], \"motivo\": \"sin noticias\"}"))
    #expect(vacio?.disponible == false && vacio?.motivo == "sin noticias" && vacio?.total == 0)
    #expect(NoticiasCentro.enlaceSeguro("file:///etc/passwd") == nil && NoticiasCentro.enlaceSeguro("http://a.b") != nil)
}

@Test("Reuniones: el resumen se recorta a tres frases sin cortar una a la mitad")
func resumenActaTresFrases() {
    let largo = "Se aprobó la cláusula. El anexo llega el viernes. Falta confirmar las fechas. Queda pendiente la plantilla. Y algo más."
    #expect(LectorActa.frases(largo) == "Se aprobó la cláusula. El anexo llega el viernes. Falta confirmar las fechas.")
    #expect(LectorActa.frases("Una sola frase sin punto") == "Una sola frase sin punto")
    #expect(LectorActa.frases("Una. Dos.") == "Una. Dos.")
    #expect(LectorActa.frases("Uno.\n\nDos. Tres. Cuatro.", maximo: 2) == "Uno. Dos.")
}
