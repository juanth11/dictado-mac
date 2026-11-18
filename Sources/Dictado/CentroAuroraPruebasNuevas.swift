import DictadoKit
import Foundation

// Datos para los renders de las secciones nuevas del Centro (Consumo, Herramientas, Finanzas, Noticias, Automatizaciones). Dos orígenes:
//   - Sin nada configurado: datos INVENTADOS (nombres y cifras de mentira), los mismos que usa la prueba de memoria.
//   - Con `DICTADO_CENTRO_DATOS=<carpeta>`: lo que imprimieron los subcomandos reales (`consumo.json`, `herramientas.json`, `finanzas.json`,
//     `noticias.json`, `automatizaciones.json`, hechos con `python3 -m centro <cmd> --json > carpeta/<cmd>.json`). Para ver el diseño con tus
//     datos sin abrir la ventana. Nada se lee del centro ni se escribe.

enum DatosNuevasDeMuestra {
    static func carpeta() -> URL? {
        ProcessInfo.processInfo.environment["DICTADO_CENTRO_DATOS"].map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
    }

    private static func archivo(_ nombre: String) -> Data? {
        carpeta().flatMap { try? Data(contentsOf: $0.appendingPathComponent(nombre + ".json")) }
    }

    static func consumo(ahora: Date) -> Consumo {
        if let d = archivo("consumo"), let c = ConsumoCentro.decodificar(d) { return c }
        let cal = Calendar.current
        func dias(_ base: Double, hermes: Bool = false) -> [DiaConsumo] {
            (0..<30).map { n in
                let f = cal.date(byAdding: .day, value: n - 29, to: cal.startOfDay(for: ahora)) ?? ahora
                let c = cal.dateComponents([.year, .month, .day, .weekday], from: f)
                let dia = String(format: "%04d-%02d-%02d", c.year ?? 2026, c.month ?? 1, c.day ?? 1)
                let finDeSemana = c.weekday == 1 || c.weekday == 7
                let onda = 0.55 + 0.45 * sin(Double(n) * 0.9) * sin(Double(n) * 0.37 + 1)
                let usd = max(0, base * onda * (finDeSemana ? 0.25 : 1))
                if n < 4 && hermes { return DiaConsumo(dia: dia, cifras: CifrasConsumo()) }
                return DiaConsumo(dia: dia, cifras: CifrasConsumo(mensajes: Int(usd * 6) + 3, entrada: Int(usd * 4_000), salida: Int(usd * 9_000),
                                                                cacheLectura: Int(usd * 2_600_000), cacheEscritura: Int(usd * 41_000), costoUSD: usd))
            }
        }
        func total(_ d: [DiaConsumo], _ n: Int) -> CifrasConsumo {
            let t = d.suffix(n).map(\.cifras)
            return CifrasConsumo(mensajes: t.reduce(0) { $0 + $1.mensajes }, entrada: t.reduce(0) { $0 + $1.entrada }, salida: t.reduce(0) { $0 + $1.salida },
                                 cacheLectura: t.reduce(0) { $0 + $1.cacheLectura }, cacheEscritura: t.reduce(0) { $0 + $1.cacheEscritura }, costoUSD: t.reduce(0) { $0 + $1.costoUSD })
        }
        func parte(_ nombre: String, _ f: Double, _ d: [DiaConsumo]) -> ItemConsumo {
            let t = total(d, 30)
            return ItemConsumo(nombre: nombre, cifras: CifrasConsumo(mensajes: Int(Double(t.mensajes) * f), entrada: Int(Double(t.entrada) * f), salida: Int(Double(t.salida) * f),
                                                                    cacheLectura: Int(Double(t.cacheLectura) * f), cacheEscritura: Int(Double(t.cacheEscritura) * f), costoUSD: t.costoUSD * f))
        }
        let cc = dias(150)
        let h = dias(0.05, hermes: true)
        let claude = FuenteConsumo(
            disponible: true, primerDia: cc.first?.dia, dias: cc,
            modelos: [parte("Opus 5.5", 0.74, cc), parte("Sonnet 5.5", 0.2, cc), parte("Fable 5.2", 0.05, cc), parte("Haiku 5.5", 0.01, cc)],
            proyectos: [parte("proyecto-uno", 0.4, cc), parte("proyecto-dos", 0.23, cc), parte("proyecto-tres", 0.12, cc), parte("proyecto-cuatro", 0.09, cc),
                        parte("proyecto-cinco", 0.07, cc), parte("Otros", 0.09, cc)],
            hoy: total(cc, 1), ayer: total(Array(cc.dropLast()), 1), sieteDias: total(cc, 7), treintaDias: total(cc, 30), fuente: "~/.claude/projects (solo lectura)", incluyeSubagentes: true)
        let hermes = FuenteConsumo(
            disponible: true, primerDia: h.first?.dia, dias: h,
            modelos: [parte("Haiku 5.5", 1, h)], proyectos: [parte("tarea-diaria", 0.4, h), parte("tarea-semanal", 0.3, h), parte("sensor", 0.2, h), parte("reflexión", 0.1, h)],
            hoy: total(h, 1), sieteDias: total(h, 7), treintaDias: total(h, 30), fuente: "state.db del VPS (solo lectura)", costoFuente: "tarifas de Anthropic",
            leido: ahora.addingTimeInterval(-180))
        return Consumo(generado: ahora, pricingVersion: "2026-11-16", claudeCode: claude, hermes: hermes)
    }

    static func consumoSin() -> Consumo {
        Consumo(claudeCode: FuenteConsumo(disponible: false, motivo: "No hay mensajes de Claude Code con uso registrado en esa ventana."),
                hermes: FuenteConsumo(disponible: false, desactualizado: true, motivo: "el VPS no respondió y no hay una lectura anterior"))
    }

    static func herramientas(ahora: Date) -> Herramientas {
        if let d = archivo("herramientas"), let h = HerramientasCentro.decodificar(d) { return h }
        func uso(_ s: Int, _ t: Int, _ hace: TimeInterval = 3600, tools: [(nombre: String, usos: Int)] = []) -> UsoHerramienta {
            UsoHerramienta(usos7: s, usos30: t, ultimoUso: t > 0 ? ahora.addingTimeInterval(-hace) : nil, herramientas: tools)
        }
        return Herramientas(
            generado: ahora, usoDesde: "2026-10-18",
            servidores: [
                ServidorMCP(nombre: "navegador", tipo: "http", destino: "mcp.ejemplo.dev", uso: uso(203, 734, 600, tools: [("abrir", 400), ("leer", 220), ("buscar", 114)])),
                ServidorMCP(nombre: "documentos", tipo: "stdio", destino: "uvx", uso: uso(21, 22, 86_400)),
                ServidorMCP(nombre: "calendario", tipo: "stdio", destino: "uv", uso: uso(138, 264, 7200)),
                ServidorMCP(nombre: "registros", tipo: "http", destino: "api.ejemplo.co", uso: uso(55, 284, 5400)),
                ServidorMCP(nombre: "diagramas", tipo: "stdio", destino: "npx", uso: uso(0, 0)),
                ServidorMCP(nombre: "analítica", tipo: "stdio", destino: "uvx", uso: uso(0, 0)),
                ServidorMCP(nombre: "búsqueda web", tipo: "http", destino: "mcp.otro.dev", uso: uso(0, 1, 1_000_000)),
                ServidorMCP(nombre: "referencias", alcance: "proyecto: mockups", activo: false, tipo: "http", destino: "api.ref.design", uso: uso(0, 0)),
            ],
            integrados: [ServidorMCP(nombre: "ccd_turn", alcance: "integrado", uso: uso(1579, 4348, 120)), ServidorMCP(nombre: "Claude_Browser", alcance: "integrado", uso: uso(1474, 6316, 60))],
            skills: [
                SkillInstalada(nombre: "diseño-iterativo", descripcion: "Construye y critica cada pieza hasta que gane la referencia.", uso: uso(0, 7, 300_000)),
                SkillInstalada(nombre: "marca-premium", descripcion: "Diseño de interfaces con criterio de producto.", uso: uso(1, 8, 20_000)),
                SkillInstalada(nombre: "scroll-film", descripcion: "Sitios con scroll cinematográfico.", uso: uso(0, 4, 500_000)),
                SkillInstalada(nombre: "ffmpeg", descripcion: "Convierte audio y video.", uso: uso(0, 0)),
                SkillInstalada(nombre: "redacción", descripcion: "Texto claro, sin relleno.", uso: uso(0, 0)),
                SkillInstalada(nombre: "antigua", descripcion: "Ya no se usa.", activa: false, uso: uso(0, 0)),
            ],
            skillsEnReserva: 168,
            plugins: [PluginInstalado(nombre: "ayudantes", origen: "propios", version: "0.2.1"), PluginInstalado(nombre: "brief", origen: "propios", version: "0.1.2"),
                      PluginInstalado(nombre: "tablero", origen: "propios", version: "0.1.0"), PluginInstalado(nombre: "traspaso", origen: "propios", version: "0.1.0", activo: false)],
            hermes: HerramientasHermes(mcp: [("crawl", true, 5), ("archivos", true, 0), ("memoria", false, 0)], skillsTotal: 76, herramientas: [("terminal", 195)], leido: ahora))
    }

    static func finanzas(ahora: Date) -> Finanzas {
        if let d = archivo("finanzas"), let f = FinanzasCentro.decodificar(d) { return f }
        let cal = Calendar.current
        func en(_ d: Int) -> Date { cal.date(byAdding: .day, value: d, to: cal.startOfDay(for: ahora)) ?? ahora }
        return Finanzas(
            disponible: true, actualizado: en(-1), diasSinActualizar: 1, patrimonio: 118_400_000, delta: 24_100_000, liquidez: 37_600_000, netoMes: 450_000,
            ingresoMes: 2_750_000, egresoMes: 2_300_000, colchon: 10_600_000, colchonPiso: 21_000_000, colchonMeta: 27_000_000,
            historico: [MesFinanzas(mes: "2026-02", ingreso: 2_330_000, egreso: 1_600_000, neto: 730_000), MesFinanzas(mes: "2026-03", ingreso: 2_810_000, egreso: 1_930_000, neto: 880_000),
                        MesFinanzas(mes: "2026-04", ingreso: 2_480_000, egreso: 2_490_000, neto: -10_000), MesFinanzas(mes: "2026-05", ingreso: 2_520_000, egreso: 1_180_000, neto: 1_340_000),
                        MesFinanzas(mes: "2026-06", ingreso: 4_790_000, egreso: 4_050_000, neto: 740_000), MesFinanzas(mes: "2026-07", ingreso: 1_930_000, egreso: 1_580_000, neto: 350_000)],
            pagos: [PagoProximo(concepto: "Cuota de la hipoteca", monto: 570_000, vence: en(7), dias: 7, critico: true), PagoProximo(concepto: "Arriendo", monto: 1_450_000, vence: en(14), dias: 14, critico: true),
                    PagoProximo(concepto: "Internet del hogar", monto: 56_000, vence: en(15), dias: 15), PagoProximo(concepto: "Administración", monto: 256_000, vence: en(19), dias: 19, critico: true),
                    PagoProximo(concepto: "Seguridad social", monto: 499_000, vence: en(19), dias: 19, critico: true)],
            proyeccionDisponible: false, proyeccionFuente: FuenteFechada(fecha: en(-133), dias: 133), orbitaDisponible: true, orbitaFuente: FuenteFechada(fecha: en(-133), dias: 133), mrr: 2_680_000,
            enlace: "ruta/al/tablero.html")
    }

    static func noticias(ahora: Date) -> Noticias {
        if let d = archivo("noticias"), let n = NoticiasCentro.decodificar(d) { return n }
        func n(_ id: String, _ v: String, _ t: String, _ fuente: String, _ fecha: String, _ por: String) -> NoticiaCentro {
            NoticiaCentro(id: id, vertical: v, titulo: t, fuente: fuente, fecha: fecha, porQue: por, url: URL(string: "https://ejemplo.co/" + id))
        }
        return Noticias(disponible: true, origen: "VPS (brief de las 5:00)", generado: ahora.addingTimeInterval(-9 * 3600), diasSinActualizar: 0, verticales: [
            VerticalNoticias(vertical: "Tributario", items: [
                n("1", "Tributario", "La UVT de 2027 queda definida y cambia los topes de la renta", "Revista de ejemplo", "10 nov", "Revisa los topes que usas en tus cálculos de clientes."),
                n("2", "Tributario", "Vencimientos tributarios del próximo año", "Entidad de ejemplo", "13 nov", "Útil para el calendario de tus clientes."),
                n("3", "Tributario", "Rechazan la reforma y llaman a movilización", "Diario de ejemplo", "11 nov", "Puede mover el calendario legislativo."),
                n("4", "Tributario", "Un experto advierte que la reforma carece de sustento técnico", "Diario de ejemplo", "9 nov", "Argumentos para tus memos.")]),
            VerticalNoticias(vertical: "Pagos", items: [n("5", "Pagos", "Las stablecoins ganan terreno en la región como ahorro y vía de pago", "Portal de ejemplo", "15 nov", "Señal de demanda para tu plataforma.")]),
            VerticalNoticias(vertical: "Agentes", items: [n("6", "Agentes", "Un comercio abraza un nuevo modelo mientras otro lo bloquea", "Periódico de ejemplo", "13 nov", "Muestra cómo se mueve el comercio con agentes.")]),
        ])
    }

    static func noticiasSin() -> Noticias {
        Noticias(disponible: false, motivo: "sin noticias: el radar no ha publicado y el servidor no respondió")
    }

    static func automatizaciones(ahora: Date) -> Automatizaciones {
        if let d = archivo("automatizaciones"), let a = AutomatizacionesCentro.decodificar(d) { return a }
        func en(_ dias: Int, _ h: Int, _ m: Int = 0) -> Date {
            let c = Calendar.current
            return c.date(bySettingHour: h, minute: m, second: 0, of: c.date(byAdding: .day, value: dias, to: c.startOfDay(for: ahora)) ?? ahora) ?? ahora
        }
        func i(_ id: String, _ origen: String, _ nombre: String, _ horario: String, _ estado: EstadoAutomatizacion, ultima: Date? = nil, proxima: Date? = nil, que: String = "",
               detalle: String = "", desde: Date? = nil, dias: Int? = nil, activo: Bool = true) -> ItemAutomatizacion {
            ItemAutomatizacion(id: id, origen: origen, nombre: nombre, queHace: que, horario: horario, activo: activo, ultima: ultima, proxima: proxima, resultado: estado == .fallo ? "error" : "ok",
                               detalle: detalle, estado: estado, paradoDesde: desde, diasParado: dias)
        }
        let items = [
            i("a", "claude", "ritual-diario-cerebro", "lun a vie a las 4:45", .parado, ultima: en(-116, 12, 24), que: "Prepara el día y revisa el cerebro.", desde: en(-116, 12, 24), dias: 116),
            i("b", "feeders", "Feeders de _sistema/status", "a pedido", .parado, ultima: en(-133, 1, 16), que: "18 archivos de estado (tokens, sesiones, skills…)", desde: en(-133, 1, 16), dias: 133),
            i("c", "launchagent", "co.ejemplo.barrido-0530", "todos los días a las 5:30", .atrasado, ultima: en(-1, 5, 33), que: "barrido-0530.sh: Revisa los avisos de la mañana", desde: en(-1, 5, 33), dias: 1),
            i("d", "hermes", "centro-brief", "todos los días a las 5:30", .alDia, ultima: en(0, 5, 30), proxima: en(1, 5, 30)),
            i("e", "hermes", "centro-radar", "todos los días a las 5:00", .alDia, ultima: en(0, 5, 0), proxima: en(1, 5, 0)),
            i("f", "hermes", "tarea-sensor", "cada 15 min", .alDia, ultima: en(0, 14, 45), proxima: en(0, 15, 0)),
            i("g", "hermes", "tarea-semanal", "lun a las 10:00", .alDia, ultima: en(0, 10, 1), proxima: en(7, 10, 0)),
            i("h", "launchagent", "co.ejemplo.respaldo", "todos los días a las 7:30, 12:30 y 18:30", .alDia, ultima: en(0, 12, 36)),
            i("j", "tablero", "Corridas de claude-code", "cuando trabaja el agente", .alDia, ultima: en(0, 13, 11)),
            i("k", "vps-cron", "sincronizar.sh", "cada 10 min", .sinDato, detalle: "su registro no cambia desde el 4/11; si no escribe nada, es normal"),
            i("l", "claude", "Recibos del mes (días 2 y 20)", "los días 2 y 20 a las 8:00", .sinDato, proxima: en(4, 8, 0)),
            i("m", "hermes", "health-check", "cada 30 min", .apagado, detalle: "en pausa desde el 11/5", desde: en(-189, 11, 30), dias: 189, activo: false),
            i("n", "hermes", "inbox-process", "todos los días a las 3:30", .apagado, detalle: "en pausa desde el 10/10", desde: en(-37, 3, 31), dias: 37, activo: false),
            i("o", "claude", "Recordatorio único", "una vez: 29/10 08:00", .apagado, detalle: "ya se cumplió", activo: false),
        ]
        var r = ResumenAutomatizaciones(total: items.count)
        for x in items {
            switch x.estado {
            case .fallo: r.fallo += 1
            case .parado: r.parado += 1
            case .atrasado: r.atrasado += 1
            case .alDia: r.alDia += 1
            case .sinDato: r.sinDato += 1
            case .apagado: r.apagado += 1
            }
        }
        return Automatizaciones(generado: ahora, resumen: r, fuentes: [
            FuenteAutomatizacion(id: "launchagent", nombre: "Mac · LaunchAgents", total: 2), FuenteAutomatizacion(id: "crontab", nombre: "Mac · crontab", total: 0, nota: "sin entradas en el crontab"),
            FuenteAutomatizacion(id: "claude", nombre: "Mac · tareas de Claude", total: 3), FuenteAutomatizacion(id: "feeders", nombre: "Mac · feeders de estado", total: 1),
            FuenteAutomatizacion(id: "tablero", nombre: "Mac · agentes del Tablero", total: 1), FuenteAutomatizacion(id: "hermes", nombre: "VPS · trabajos de Hermes", total: 6),
            FuenteAutomatizacion(id: "vps-cron", nombre: "VPS · cron del servidor", total: 1)], items: items, vpsLeido: ahora.addingTimeInterval(-240))
    }
}


// MARK: - Hoy

/// El estado del día de la muestra de Hoy, inventado: nombres, correos y noticias de mentira. `.sin` es el día en que nada llegó.
enum DatosHoyDeMuestra {
    enum Caso { case completo, sin }

    static func estado(_ caso: Caso) -> EstadoCentro? {
        let texto: String
        switch caso {
        case .sin:
            texto = #"{"brief.json": {"modelo": "Modelo de prueba", "fecha": "Domingo 15 de noviembre", "fecha_iso": "2026-11-15", "semana": 46, "foco": {"titulo": "Foco de ayer", "porque": "x"}, "prioridades": [], "bueno_saber": []}, "local": {"cerebro": "/tmp/cerebro", "inbox": 0}, "vps": false}"#
        case .completo:
            texto = completo
        }
        return EstadoCentro.decodificar(Data(texto.utf8))
    }

    private static let completo = #"""
    {"vps": true,
     "local": {"cerebro": "/tmp/cerebro", "inbox": 80, "inbox_hermes": 3},
     "brief.json": {"modelo": "Modelo de prueba", "generado": "2026-11-16T05:30:20-05:00", "fecha": "Lunes 16 de noviembre", "fecha_iso": "2026-11-16", "semana": 47,
       "clima": {"ciudad": "Bogotá", "temp": 9, "cielo": "Chubascos", "max": 23, "min": 9, "simbolo": "cloud.heavyrain"},
       "foco": {"titulo": "Cerrar el contrato marco con el Cliente Demo", "porque": "Es lo único que bloquea la firma del viernes y el cliente ya devolvió sus comentarios."},
       "prioridades": [
         {"texto": "Enviar el poder firmado", "vertical": "Lumina", "meta": "Cerrar el trimestre sin pendientes", "minutos": 30, "hecha": false},
         {"texto": "Revisar la cláusula de exclusividad", "vertical": "Lumina", "meta": "Contrato marco", "minutos": 45, "hecha": false},
         {"texto": "Preparar el informe del comité", "vertical": "Consultoría", "minutos": 60, "hecha": false}],
       "bueno_saber": ["La UVT de 2027 sale esta semana."]},
     "manana.json": {"version": 1, "generado": "2026-11-16T05:45:10-05:00", "estado": "ok", "fecha_iso": "2026-11-16",
       "agenda": {"leida": true, "eventos": []},
       "correos": {"leidos": true, "total": 16, "lista": [
         {"de": "Ana Pérez", "asunto": "Contrato marco: comentarios finales", "fecha": "2026-11-16T08:10:00-05:00", "sin_leer": true, "enlace": "https://mail.google.com/mail/u/0/#inbox/aaa1"},
         {"de": "Cliente Demo S. A. S.", "asunto": "Re: Fechas de entrega del anexo técnico", "fecha": "2026-11-16T07:02:00-05:00", "sin_leer": true, "enlace": "https://mail.google.com/mail/u/0/#inbox/aaa2"},
         {"de": "Carlos Rojas", "asunto": "Pregunta sobre la retención en la fuente", "fecha": "2026-11-15T16:40:00-05:00", "sin_leer": false, "enlace": "https://mail.google.com/mail/u/0/#inbox/aaa3"},
         {"de": "Soporte Contable Demo", "asunto": "Soportes del cierre de octubre", "fecha": "2026-11-15T10:15:00-05:00", "sin_leer": false, "enlace": "https://mail.google.com/mail/u/0/#inbox/aaa4"},
         {"de": "Laura Gómez", "asunto": "¿Podemos mover la reunión del jueves?", "fecha": "2026-11-14T18:30:00-05:00", "sin_leer": false, "enlace": "https://mail.google.com/mail/u/0/#inbox/aaa5"},
         {"de": "Notaría Demo", "asunto": "Cita para la firma del poder", "fecha": "2026-11-13T09:00:00-05:00", "sin_leer": false, "enlace": "https://mail.google.com/mail/u/0/#inbox/aaa6"},
         {"de": "Pedro Díaz", "asunto": "Borrador del memo de IVA", "fecha": "2026-11-13T08:00:00-05:00", "sin_leer": false, "enlace": "https://mail.google.com/mail/u/0/#inbox/aaa7"},
         {"de": "Marta Ruiz", "asunto": "Factura de noviembre", "fecha": "2026-11-12T11:00:00-05:00", "sin_leer": false, "enlace": "https://mail.google.com/mail/u/0/#inbox/aaa8"}]},
       "inbox": 80, "reuniones": 4, "foco": {"titulo": "Cerrar el contrato marco con el Cliente Demo", "porque": "x"}},
     "noticias.json": {"generado": "2026-11-16T05:30:20-05:00", "items": [
       {"vertical": "Lumina", "titulo": "La autoridad tributaria publica el calendario de vencimientos del próximo año", "fuente": "Diario Económico", "fecha": "15 nov", "por_que": "x", "url": "https://ejemplo.co/a"},
       {"vertical": "Nimbo", "titulo": "El banco central mantiene la tasa de referencia y abre consulta sobre pagos transfronterizos", "fuente": "Revista Fiscal", "fecha": "15 nov", "por_que": "x", "url": "https://ejemplo.co/b"},
       {"vertical": "Orbita", "titulo": "Las empresas medianas adoptan agentes de IA para soporte y cobranza", "fuente": "Gaceta Digital", "fecha": "16 nov", "por_que": "x", "url": "https://ejemplo.co/c"},
       {"vertical": "Tesis", "titulo": "No debería verse", "fuente": "Otra", "fecha": "16 nov", "por_que": "x"}]}}
    """#
}
