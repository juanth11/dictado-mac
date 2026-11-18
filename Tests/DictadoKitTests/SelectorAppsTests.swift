import Testing
@testable import DictadoKit

private typealias C = ClasificadorSelector

// MARK: - Clasificador de teclas

@Test("Selector: ⌘Tab arranca el selector y se consume; sin ⌘ pasa")
func selector_inicio() {
    var c = ClasificadorSelector()
    let sinCmd = c.teclaAbajo(codigo: C.codigoTab, mods: [])
    #expect(sinCmd.consumir == false && sinCmd.entrada == nil && !c.activo)
    let r = c.teclaAbajo(codigo: C.codigoTab, mods: .cmd)
    #expect(r.consumir && r.entrada == .iniciar(atras: false) && c.activo)
}

@Test("Selector: ⌘⇧Tab arranca hacia atrás; con ⌥ o ⌃ (hyper, otros atajos) no se toca")
func selector_atrasYAtajosAjenos() {
    var c = ClasificadorSelector()
    let r1 = c.teclaAbajo(codigo: C.codigoTab, mods: [.cmd, .shift]).entrada
    #expect(r1 == .iniciar(atras: true))
    var d = ClasificadorSelector()
    let hyper: ModsSelector = [.cmd, .shift, .opcion, .control]
    let r = d.teclaAbajo(codigo: C.codigoTab, mods: hyper)
    #expect(r.consumir == false && r.entrada == nil && !d.activo)
    let r2 = d.teclaAbajo(codigo: C.codigoTab, mods: [.cmd, .opcion]).consumir
    #expect(r2 == false)
}

@Test("Selector: con el selector abierto Tab, ` y las flechas se consumen y avisan")
func selector_teclasAbiertas() {
    var c = ClasificadorSelector()
    _ = c.teclaAbajo(codigo: C.codigoTab, mods: .cmd)
    let r3 = c.teclaAbajo(codigo: C.codigoTab, mods: .cmd).entrada
    #expect(r3 == .tecla(.tab(atras: false)))
    let r4 = c.teclaAbajo(codigo: C.codigoTab, mods: [.cmd, .shift]).entrada
    #expect(r4 == .tecla(.tab(atras: true)))
    let r5 = c.teclaAbajo(codigo: C.codigoAcento, mods: .cmd).entrada
    #expect(r5 == .tecla(.acento(atras: false)))
    let r6 = c.teclaAbajo(codigo: C.codigoAcento, mods: [.cmd, .shift]).entrada
    #expect(r6 == .tecla(.acento(atras: true)))
    let r7 = c.teclaAbajo(codigo: C.codigoAbajo, mods: .cmd).entrada
    #expect(r7 == .tecla(.abajo))
    let r8 = c.teclaAbajo(codigo: C.codigoArriba, mods: .cmd).entrada
    #expect(r8 == .tecla(.arriba))
    let r9 = c.teclaAbajo(codigo: C.codigoIzquierda, mods: .cmd).entrada
    #expect(r9 == .tecla(.izquierda))
    let r10 = c.teclaAbajo(codigo: C.codigoDerecha, mods: .cmd).entrada
    #expect(r10 == .tecla(.derecha))
    #expect(c.activo)
}

@Test("Selector: otra tecla con el selector abierto se consume sin avisar (no llega a la app de atrás)")
func selector_otraTeclaSeConsume() {
    var c = ClasificadorSelector()
    _ = c.teclaAbajo(codigo: C.codigoTab, mods: .cmd)
    let r = c.teclaAbajo(codigo: 12, mods: .cmd)   // Q
    #expect(r.consumir && r.entrada == nil && c.activo)
}

@Test("Selector: Esc cancela, Return confirma y los dos cierran la sesión")
func selector_escYReturn() {
    var c = ClasificadorSelector()
    _ = c.teclaAbajo(codigo: C.codigoTab, mods: .cmd)
    let r11 = c.teclaAbajo(codigo: C.codigoEsc, mods: .cmd).entrada
    #expect(r11 == .cancelar)
    #expect(!c.activo)
    // ⌘ sigue apretado y ya no hay sesión: soltarlo no avisa nada
    let r12 = c.modificadores([])
    #expect(r12 == nil)
    _ = c.teclaAbajo(codigo: C.codigoTab, mods: .cmd)
    let r13 = c.teclaAbajo(codigo: C.codigoReturn, mods: .cmd).entrada
    #expect(r13 == .confirmar)
    #expect(!c.activo)
}

@Test("Selector: soltar ⌘ avisa una sola vez y nunca consume")
func selector_soltarCmd() {
    var c = ClasificadorSelector()
    _ = c.teclaAbajo(codigo: C.codigoTab, mods: .cmd)
    let r14 = c.modificadores([.cmd, .shift])
    #expect(r14 == nil)     // soltar solo ⇧ no cuent)
    let r15 = c.modificadores([.shift])
    #expect(r15 == .soltarCmd)
    #expect(!c.activo)
    let r16 = c.modificadores([])
    #expect(r16 == nil)
}

@Test("Selector: el soltar de una tecla consumida también se consume, una sola vez")
func selector_teclaArribaConsumida() {
    var c = ClasificadorSelector()
    _ = c.teclaAbajo(codigo: C.codigoTab, mods: .cmd)
    let r17 = c.teclaArriba(codigo: C.codigoTab)
    #expect(r17)
    let r18 = c.teclaArriba(codigo: C.codigoTab)
    #expect(r18 == false)
    let r19 = c.teclaArriba(codigo: 0)
    #expect(r19 == false)
}

@Test("Selector: si se perdió el aviso de soltar ⌘, la siguiente tecla sin ⌘ cierra y pasa")
func selector_avisoPerdido() {
    var c = ClasificadorSelector()
    _ = c.teclaAbajo(codigo: C.codigoTab, mods: .cmd)
    let r = c.teclaAbajo(codigo: 0, mods: [])
    #expect(r.consumir == false && r.entrada == .soltarCmd && !c.activo)
}

@Test("Selector: reiniciar dice si había sesión y deja todo limpio")
func selector_reiniciar() {
    var c = ClasificadorSelector()
    let r20 = c.reiniciar()
    #expect(r20 == false)
    _ = c.teclaAbajo(codigo: C.codigoTab, mods: .cmd)
    let r21 = c.reiniciar()
    #expect(r21)
    #expect(!c.activo && c.teclaArriba(codigo: C.codigoTab) == false)
}

// MARK: - Máquina

private func maquina(apps: Int = 5, elementos: Int = 0, atras: Bool = false) -> MaquinaSelector {
    var m = MaquinaSelector()
    m.iniciar(atras: atras, totalApps: apps)
    m.ajustarElementos(total: elementos, inicial: 0)
    return m
}

@Test("Máquina: ⌘Tab salta a la app anterior (la 1); con una sola app se queda; ⌘⇧Tab empieza por la última")
func maquina_inicio() {
    #expect(maquina().app == 1)
    #expect(maquina(apps: 1).app == 0)
    #expect(maquina(atras: true).app == 4)
    #expect(maquina().fase == .esperando)
    #expect(maquina(apps: 0).fase == .reposo)
}

@Test("Máquina: toque rápido (soltar antes de mostrar) va a la app anterior sin panel")
func maquina_toqueRapido() {
    var m = maquina()
    let r22 = m.soltar()
    #expect(r22 == .confirmar(app: 1, elemento: nil, conPanel: false))
    #expect(m.fase == .reposo)
    let r23 = m.soltar()
    #expect(r23 == .nada)
}

@Test("Máquina: Tab recorre las apps con vuelta y muestra el panel")
func maquina_tabVuelta() {
    var m = maquina(apps: 3)
    let r24 = m.tecla(.tab(atras: false))
    #expect(r24)
    #expect(m.app == 2 && m.fase == .visible)
    m.tecla(.tab(atras: false))
    #expect(m.app == 0)
    m.tecla(.tab(atras: true))
    #expect(m.app == 2)
    m.tecla(.izquierda); #expect(m.app == 1)
    m.tecla(.derecha); #expect(m.app == 2)
    let r25 = m.soltar()
    #expect(r25 == .confirmar(app: 2, elemento: nil, conPanel: true))
}

@Test("Máquina: ↓ entra a la lista en la pestaña activa, ↑ sale a la fila de apps")
func maquina_listaConFlechas() {
    var m = maquina(elementos: 5)
    m.ajustarElementos(total: 5, inicial: 3)
    m.tecla(.abajo); #expect(m.elemento == 3)
    m.tecla(.abajo); #expect(m.elemento == 4)
    m.tecla(.abajo); #expect(m.elemento == 4)   // no da la vuelta
    m.tecla(.arriba); m.tecla(.arriba); m.tecla(.arriba); #expect(m.elemento == 1)
    m.tecla(.arriba); #expect(m.elemento == 0)
    m.tecla(.arriba); #expect(m.elemento == nil)
    m.tecla(.arriba); #expect(m.elemento == nil)
}

@Test("Máquina: sin elementos ↓ no hace nada; cambiar de app con ←/→ sale de la lista y la vacía")
func maquina_cambioDeAppSaleDeLaLista() {
    var vacia = maquina(elementos: 0)
    let r26 = vacia.tecla(.abajo)
    #expect(r26 == false && vacia.elemento == nil)
    var m = maquina(elementos: 4)
    m.tecla(.abajo); #expect(m.elemento == 0)
    let r27 = m.tecla(.derecha)
    #expect(r27)
    #expect(m.elemento == nil && m.totalElementos == 0)
}

@Test("Máquina: ` cicla las ventanas de la app con vuelta; en la app de adelante empieza por la segunda")
func maquina_acento() {
    var m = maquina(apps: 4, elementos: 3)
    m.tecla(.izquierda)    // 1 → 0: la app de adelante
    #expect(m.app == 0)
    m.ajustarElementos(total: 3, inicial: 0)
    m.tecla(.acento(atras: false)); #expect(m.elemento == 1)
    m.tecla(.acento(atras: false)); #expect(m.elemento == 2)
    m.tecla(.acento(atras: false)); #expect(m.elemento == 0)
    m.tecla(.acento(atras: true)); #expect(m.elemento == 2)
    var otra = maquina(apps: 4, elementos: 3)
    otra.tecla(.acento(atras: false)); #expect(otra.elemento == 0)
    var sola = maquina(apps: 4, elementos: 0)
    let r28 = sola.tecla(.acento(atras: false))
    #expect(r28 == false && sola.elemento == nil)
}

@Test("Máquina: soltar con un elemento elegido lo devuelve; cancelar no va a ningún lado")
func maquina_soltarYCancelar() {
    var m = maquina(elementos: 3)
    m.tecla(.abajo); m.tecla(.abajo)
    let r29 = m.soltar()
    #expect(r29 == .confirmar(app: 1, elemento: 1, conPanel: true))
    var c = maquina()
    c.tecla(.tab(atras: false))
    c.cancelar()
    #expect(c.fase == .reposo && c.soltar() == .nada)
}

@Test("Máquina: si la lista se acorta, la selección no se pasa del final")
func maquina_ajustar() {
    var m = maquina(elementos: 6)
    m.tecla(.abajo); m.tecla(.abajo); m.tecla(.abajo); m.tecla(.abajo)
    #expect(m.elemento == 3)
    m.ajustarElementos(total: 2, inicial: 0)
    #expect(m.elemento == 1)
    m.ajustarElementos(total: 0, inicial: 0)
    #expect(m.elemento == nil)
}

@Test("Máquina: en reposo las teclas no hacen nada")
func maquina_reposo() {
    var m = MaquinaSelector()
    let r30 = m.tecla(.tab(atras: false))
    #expect(r30 == false)
    #expect(m.fase == .reposo && m.app == 0)
}

// MARK: - Orden de uso

@Test("Uso: la última app va primero, sin repetirse, con tope")
func uso_registrar() {
    var l: [Int] = []
    for id in [1, 2, 3, 2, 1] { l = OrdenUso.registrar(id, en: l) }
    #expect(l == [1, 2, 3])
    #expect(OrdenUso.registrar(9, en: [1, 2, 3], limite: 3) == [9, 1, 2])
}

@Test("Uso: las apps vivas siguen el orden de uso y las que nunca se usaron van al final como vinieron")
func uso_ordenar() {
    #expect(OrdenUso.ordenar(vivos: [10, 20, 30, 40], uso: [30, 99, 10]) == [30, 10, 20, 40])
    #expect(OrdenUso.ordenar(vivos: [], uso: [1]) == [])
    #expect(OrdenUso.ordenar(vivos: [1, 1, 2], uso: [2, 2]) == [2, 1])
}

@Test("Uso: ⌘Tab dos veces seguidas vuelve a donde estabas (A→B, luego B→A)")
func uso_alternar() {
    var uso = OrdenUso.registrar(1, en: [])     // estás en la app 1
    uso = OrdenUso.registrar(2, en: uso)        // ⌘Tab a la 2
    #expect(OrdenUso.ordenar(vivos: [1, 2, 3], uso: uso)[1] == 1)
}

// MARK: - Disposición

@Test("Disposición: una fila si caben, y si no, filas parejas")
func disposicion_columnas() {
    #expect(DisposicionSelector.columnas(total: 0, anchoPantalla: 1440) == 1)
    #expect(DisposicionSelector.columnas(total: 6, anchoPantalla: 1440) == 6)
    // 1440 · 0,84 − 40 = 1169,6 → caben 12 columnas de 88
    #expect(DisposicionSelector.columnas(total: 12, anchoPantalla: 1440) == 12)
    #expect(DisposicionSelector.columnas(total: 14, anchoPantalla: 1440) == 7)
    // pantalla angosta: caben menos y se reparte parejo
    #expect(DisposicionSelector.columnas(total: 9, anchoPantalla: 800) == 5)
    #expect(DisposicionSelector.columnas(total: 40, anchoPantalla: 1440) == 10)
}

@Test("Disposición: las filas cubren todos los índices una vez")
func disposicion_filas() {
    let f = DisposicionSelector.filas(total: 11, columnas: 4)
    #expect(f == [0..<4, 4..<8, 8..<11])
    #expect(DisposicionSelector.filas(total: 0, columnas: 4).isEmpty)
    #expect(DisposicionSelector.anchoFila(columnas: 3) == 3 * 80 + 2 * 8)
}

// MARK: - Lista de ventanas y pestañas

@Test("Lista: cada ventana va seguida de sus pestañas")
func lista_aplanar() {
    let l = ListaDetalle.aplanar([ResumenVentana(pestanas: 2), ResumenVentana(pestanas: 0), ResumenVentana(pestanas: 1)])
    #expect(l == [.ventana(0), .pestana(ventana: 0, indice: 0), .pestana(ventana: 0, indice: 1), .ventana(1), .ventana(2), .pestana(ventana: 2, indice: 0)])
    #expect(l[3].indiceVentana == 1)
    #expect(ListaDetalle.aplanar([]).isEmpty)
}

@Test("Lista: al bajar se cae en la pestaña activa de la ventana de adelante")
func lista_inicial() {
    #expect(ListaDetalle.inicial([ResumenVentana(pestanas: 5, activa: 2), ResumenVentana(pestanas: 3)]) == 3)
    #expect(ListaDetalle.inicial([ResumenVentana(pestanas: 5)]) == 0)
    #expect(ListaDetalle.inicial([ResumenVentana(pestanas: 2, activa: 7)]) == 0)
    #expect(ListaDetalle.inicial([]) == 0)
}

@Test("Lista visible: si todo cabe se ve todo; si no, la selección siempre queda a la vista")
func lista_visibles() {
    let alturas = [64.0, 40, 40, 40, 40, 64, 40, 40]
    #expect(ListaDetalle.visibles(alturas: alturas, hueco: 4, seleccion: nil, maximo: 1000) == 0..<8)
    #expect(ListaDetalle.visibles(alturas: [], hueco: 4, seleccion: nil, maximo: 100) == 0..<0)
    let corto = ListaDetalle.visibles(alturas: alturas, hueco: 4, seleccion: nil, maximo: 150)
    #expect(corto.lowerBound == 0 && corto.count >= 2)
    for s in 0..<alturas.count {
        let r = ListaDetalle.visibles(alturas: alturas, hueco: 4, seleccion: s, maximo: 150)
        #expect(r.contains(s))
        let alto = r.map { alturas[$0] }.reduce(0, +) + Double(max(0, r.count - 1)) * 4
        #expect(alto <= 150 || r.count == 1)
    }
}

@Test("Lista visible: una fila más alta que el máximo se muestra sola")
func lista_visibleGigante() {
    #expect(ListaDetalle.visibles(alturas: [300], hueco: 4, seleccion: 0, maximo: 100) == 0..<1)
}

// MARK: - Icono de pestaña

@Test("Pestaña: dominio sin www, inicial y tono estables")
func pestana_etiqueta() {
    #expect(EtiquetaPestana.dominio(de: "https://www.notion.so/plan") == "notion.so")
    #expect(EtiquetaPestana.dominio(de: "chrome://newtab") == "newtab")
    #expect(EtiquetaPestana.dominio(de: "") == "")
    #expect(EtiquetaPestana.inicial(titulo: "Plan", url: "https://mail.google.com/x") == "M")
    #expect(EtiquetaPestana.inicial(titulo: "ñandú", url: "") == "Ñ")
    #expect(EtiquetaPestana.inicial(titulo: "", url: "") == "")
    #expect(EtiquetaPestana.tono(de: "notion.so") == EtiquetaPestana.tono(de: "notion.so"))
    #expect((0..<EtiquetaPestana.tonos).contains(EtiquetaPestana.tono(de: "github.com")))
    #expect(EtiquetaPestana.tono(de: "a.com") != EtiquetaPestana.tono(de: "b.com") || EtiquetaPestana.tono(de: "b.com") != EtiquetaPestana.tono(de: "c.com"))
}

@Test("Guion de pestañas: con URL añade un campo y la lectura lo recoge; sin URL todo queda como antes")
func guion_conURL() {
    let con = NavegadoresDock.guionListar(bundleID: "dk.kildahl.cra", familia: .cra, conURL: true)
    let sin = NavegadoresDock.guionListar(bundleID: "dk.kildahl.cra", familia: .cra)
    #expect(con.contains("URL of t") && !sin.contains("URL of t"))
    let rs = NavegadoresDock.separadorRegistro, us = NavegadoresDock.separadorCampo
    let texto = ["1", "w1", "Ventana", "1", "t1", "Notion", "true", "https://notion.so"].joined(separator: us) + rs
        + ["1", "w1", "Ventana", "2", "t2", "Sin URL", "false"].joined(separator: us) + rs
    let v = NavegadoresDock.leer(texto)
    #expect(v.count == 1 && v[0].pestanas.count == 2)
    #expect(v[0].pestanas[0].url == "https://notion.so" && v[0].pestanas[0].activa)
    #expect(v[0].pestanas[1].url == "")
}
