import Testing
@testable import DictadoKit

private let ejemplo = """
{"version": 1, "generado": "2026-11-16T10:48:05-05:00", "estado": "ok", "campo_nuevo": {"x": 1},
 "conteos": {"trabajando": 2, "esperan_tu_si": 1, "terminaron_hoy": 1, "terminaron_anoche": 3, "otro": 9},
 "decisiones": [
   {"id": 4, "encargo_id": 12, "corrida_id": 7, "pregunta": "¿Publico el memo a los clientes?", "opciones": ["Publicar", "Esperar", "  "],
    "respuesta": null, "creada": "2026-11-16T09:00:00-05:00", "resuelta": null, "encargo_titulo": "Memo de IVA", "extra": true},
   {"id": 5, "pregunta": "¿Sigo?", "opciones": [], "respuesta": null},
   {"id": 6, "pregunta": "Ya respondida", "opciones": [], "respuesta": "Sí"},
   {"id": 7, "pregunta": ""},
   {"sin": "id"}
 ],
 "en_curso": [
   {"id": 205, "encargo_id": null, "agente": "claude-code", "sesion": "69604d0b", "proyecto": "Mi Proyecto", "titulo": "Sistema de finanzas",
    "inicio": "2026-11-15T21:40:08-05:00", "fin": null, "estado": "trabajando", "resumen": null, "enlace": null,
    "tokens_entrada": 43051364, "tokens_salida": 80261, "modelo": "claude-opus-5-5", "costo_usd": 13.771523, "clave": "claude-code:69604d0b"},
   {"id": 206, "titulo": "Sin costo", "estado": "trabajando", "costo_usd": null, "inicio": "2026-11-16T10:00:00-05:00"},
   {"titulo": "sin id"}
 ],
 "ultimas": [
   {"id": 191, "agente": "claude-code", "titulo": "Compatibilidad", "inicio": "2026-11-15T11:23:59-05:00", "fin": "2026-11-15T23:05:53-05:00",
    "estado": "termino", "resumen": "Quedó lista.", "enlace": "claude://code/continue?session=abc", "tokens_entrada": 100, "tokens_salida": 20, "costo_usd": 0.41},
   {"id": 192, "titulo": "Otra", "inicio": "2026-11-15T10:00:00-05:00", "fin": "2026-11-15T22:00:00-05:00", "estado": "fallo", "enlace": "javascript:alert(1)"},
   {"id": 205, "titulo": "Sigue en curso", "estado": "termino", "fin": "2026-11-15T20:00:00-05:00"},
   {"id": 193, "titulo": "Estado raro", "estado": "algo-nuevo"}
 ],
 "tareas": []}
"""

@Test("Tablero: se lee el JSON, se ignoran claves nuevas y se saltan las filas mal formadas")
func tableroDecodificar() {
    let t = TableroCentro.decodificar(datosJSON(ejemplo))
    #expect(t?.version == 1 && t?.estado == "ok")
    #expect(t?.conteos == ConteosTablero(trabajando: 2, esperanTuSi: 1, terminaronHoy: 1, terminaronAnoche: 3))
    #expect(t?.generado != nil)
    // Las decisiones: la respondida, la sin pregunta y la sin id no cuentan.
    #expect(t?.decisiones.map(\.id) == [4, 5])
    #expect(t?.decisiones[0].opciones == ["Publicar", "Esperar"])
    #expect(t?.decisiones[0].encargoTitulo == "Memo de IVA" && t?.decisiones[0].encargoID == 12)
    #expect(t?.decisiones[0].respuestasPosibles == ["Publicar", "Esperar"])
    #expect(t?.decisiones[1].respuestasPosibles == ["Sí", "No"])
    #expect(t?.enCurso.map(\.id) == [205, 206])
    #expect(t?.enCurso[0].tokens == 43_131_625 && t?.enCurso[0].costoUSD == 13.771523)
    #expect(t?.enCurso[1].costoUSD == nil && t?.enCurso[1].tokens == nil)
}

@Test("Tablero: los enlaces solo son web o claude://; un estado desconocido se trata como en marcha")
func tableroEnlaces() {
    let t = TableroCentro.decodificar(datosJSON(ejemplo))
    #expect(t?.ultimas[0].enlace?.scheme == "claude")
    #expect(t?.ultimas[1].enlace == nil)
    #expect(t?.ultimas[1].estado == .fallo)
    #expect(t?.ultimas[3].estado == .trabajando)
    #expect(TableroCentro.enlaceSeguro("https://ejemplo.co/a")?.host == "ejemplo.co")
    #expect(TableroCentro.enlaceSeguro("file:///etc/passwd") == nil)
}

@Test("Tablero: una versión mayor que 1 se lee igual; sin versión, un rechazo o algo que no es el tablero, no")
func tableroVersiones() {
    #expect(TableroCentro.decodificar(datosJSON("{\"version\": 3, \"conteos\": {\"trabajando\": 4}, \"futuro\": [1,2]}"))?.version == 3)
    #expect(TableroCentro.decodificar(datosJSON("{\"version\": 3, \"conteos\": {\"trabajando\": 4}}"))?.conteos.trabajando == 4)
    #expect(TableroCentro.decodificar(datosJSON("{\"conteos\": {}}")) == nil)
    #expect(TableroCentro.decodificar(datosJSON("{\"ok\": false, \"error\": \"x\"}")) == nil)
    #expect(TableroCentro.decodificar(datosJSON("[]")) == nil)
    #expect(TableroCentro.decodificar(datosJSON("sin novedades")) == nil)
    #expect(TableroCentro.decodificar(datosJSON("{\"version\": 1}")) == nil)
    // Sin conteos, salen de las listas.
    let t = TableroCentro.decodificar(datosJSON("{\"version\": 1, \"en_curso\": [{\"id\": 1, \"titulo\": \"a\", \"estado\": \"trabajando\"}], \"decisiones\": [{\"id\": 2, \"pregunta\": \"¿?\"}]}"))
    #expect(t?.conteos.trabajando == 1 && t?.conteos.esperanTuSi == 1)
}

@Test("Tablero: el encargo creado y la respuesta del centro")
func tableroEncargo() {
    let e = TableroCentro.decodificarEncargo(datosJSON("{\"id\": 31, \"titulo\": \"Revisar el contrato\", \"estado\": \"pendiente\", \"nuevo\": true, \"pedido\": \"x\"}"))
    #expect(e == EncargoTablero(id: 31, titulo: "Revisar el contrato", estado: "pendiente", nuevo: true))
    #expect(TableroCentro.decodificarEncargo(datosJSON("{\"ok\": false, \"error\": \"origen inválido\"}")) == nil)
    #expect(TableroCentro.decodificarEncargo(datosJSON("basura")) == nil)
    #expect(TableroCentro.aceptada(datosJSON("{\"id\": 4, \"respuesta\": \"Sí\"}")))
    #expect(!TableroCentro.aceptada(datosJSON("{\"ok\": false, \"error\": \"no existe\"}")))
    #expect(!TableroCentro.aceptada(datosJSON("")))
}

@Test("Tablero: el costo se escribe como equivalente en dólares y se oculta si no hay")
func tableroCosto() {
    #expect(TableroCentro.costo(0.41) == "US$ 0,41 equivalente")
    #expect(TableroCentro.costo(13.771523) == "US$ 13,77 equivalente")
    #expect(TableroCentro.costo(1234.5) == "US$ 1.234,50 equivalente")
    #expect(TableroCentro.costo(0) == "US$ 0,00 equivalente")
    #expect(TableroCentro.costo(0.001) == "menos de US$ 0,01 equivalente")
    #expect(TableroCentro.costo(nil) == nil)
    #expect(TableroCentro.costo(-3) == nil)
}

@Test("Tablero: tokens y tiempo en pocas letras")
func tableroTokensYTiempo() {
    #expect(TableroCentro.tokens(812) == "812")
    #expect(TableroCentro.tokens(3_400) == "3,4 k")
    #expect(TableroCentro.tokens(340_000) == "340 k")
    #expect(TableroCentro.tokens(1_200_000) == "1,2 M")
    #expect(TableroCentro.tokens(43_131_625) == "43 M")
    let ahora = f(16, 12, 0)
    #expect(TableroCentro.transcurrido(desde: f(16, 11, 18), hasta: ahora) == "42 min")
    #expect(TableroCentro.transcurrido(desde: f(16, 9, 55), hasta: ahora) == "2 h 05 min")
    #expect(TableroCentro.transcurrido(desde: nil, hasta: ahora) == nil)
    #expect(TableroCentro.transcurrido(desde: f(16, 13, 0), hasta: ahora) == "0 min")
}

@Test("Tablero: las cuentas salen del tablero si la lectura es vigente y, si no, de lo que se ve directo")
func tableroCuentas() {
    let t = Tablero(conteos: ConteosTablero(trabajando: 3, esperanTuSi: 2))
    let leido = f(16, 12, 0)
    let con = TableroCentro.cuentas(tablero: t, leido: leido, ahora: f(16, 12, 5), directoTrabajando: 1, directoEsperan: 4, esperanVivas: 4)
    #expect(con.trabajando == 3 && con.esperan == 6 && con.deTablero)
    let vieja = TableroCentro.cuentas(tablero: t, leido: leido, ahora: f(16, 12, 30), directoTrabajando: 1, directoEsperan: 4, esperanVivas: 4)
    #expect(vieja.trabajando == 1 && vieja.esperan == 4 && !vieja.deTablero)
    let sin = TableroCentro.cuentas(tablero: nil, leido: nil, ahora: leido, directoTrabajando: 2, directoEsperan: 0)
    #expect(sin.trabajando == 2 && sin.esperan == 0 && !sin.deTablero)
}

@Test("Tablero: se pide como mucho una vez por minuto")
func tableroFrecuencia() {
    let t0 = f(16, 12, 0)
    #expect(TableroCentro.tocaPedir(ultima: nil, ahora: t0))
    #expect(!TableroCentro.tocaPedir(ultima: t0, ahora: t0.addingTimeInterval(59)))
    #expect(TableroCentro.tocaPedir(ultima: t0, ahora: t0.addingTimeInterval(60)))
}

@Test("Tablero: lo terminado va sin lo que sigue en curso, lo más reciente primero")
func tableroTerminadas() {
    let t = TableroCentro.decodificar(datosJSON(ejemplo))!
    #expect(TableroCentro.terminadas(t).map(\.id) == [191, 192])   // 205 sigue en curso; 193 no ha terminado
    #expect(TableroCentro.terminadas(t, limite: 1).map(\.id) == [191])
}

@Test("Tablero: el encargo dictado lleva las primeras 80 letras de título y el texto entero de pedido")
func tableroEncargoDictado() {
    #expect(TableroCentro.tituloDeEncargo("  Revisa   el contrato   de Nimbo ") == "Revisa el contrato de Nimbo")
    let largo = String(repeating: "palabra ", count: 30)
    let titulo = TableroCentro.tituloDeEncargo(largo)
    #expect(titulo.count <= 81 && titulo.hasSuffix("…") && !titulo.contains("palabr…"))
    let a = TableroCentro.argumentosEncargo("Revisa el contrato de Nimbo")
    #expect(a == ["encargo", "nuevo", "Revisa el contrato de Nimbo", "--pedido", "Revisa el contrato de Nimbo", "--origen", "dictado", "--json"])
    #expect(TableroCentro.argumentosEncargo(largo)[4].count == largo.count - 1)   // el pedido va entero (sin el espacio final)
    #expect(TableroCentro.argumentosRespuesta(decision: 4, respuesta: "Publicar") == ["decision", "responder", "4", "Publicar", "--json"])
}
