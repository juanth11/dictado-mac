import Testing
@testable import DictadoKit

// Notas inventadas con el formato que escribe el sistema (frontmatter, resumen, secciones).
private let completa = """
---
date: 2026-11-16T14:45-05:00
source: dictado-notas
tipo: reunion
reunion: Comité de revisión del contrato
inicio: 2026-11-16T14:00
modelo: modelo-de-prueba
transcripcion: /tmp/inventada.txt
evento: Reunión semanal
---

# Notas · Comité de revisión del contrato

A esa hora el calendario tenía «Reunión semanal», pero lo que se habló es otra cosa.

El comité aprobó la nueva cláusula de confidencialidad. Falta que el cliente confirme las fechas.

Quedó pendiente la versión final del anexo.

## Decisiones

- Se usa la plantilla nueva
- El anexo sale el viernes

## Pendientes

- [ ] Tú · enviar el anexo firmado · viernes · si: al terminar la revisión · (Contratos)
  > «yo envío el anexo firmado el viernes»
- [x] Tú · llamar a la notaría · mañana
  > «la llamo mañana a primera hora»
- [ ] Marta · preparar el acta
- [ ] Tú · revisar

## Descartado

- Pedro · mandar el presupuesto
- Tú · revisar (vago)

## Correo de seguimiento (borrador)

```text
Estimado/a Marta,

Quedamos en enviar el anexo el viernes.
## Esto no es una sección
Un saludo.
```

## Para la bitácora (wiki/reuniones.md)

- 2026-11-16 · Marta · Contrato · aprobado

## Transcripción

Completa en el Mac, fuera del cerebro.
"""

@Test("Acta: título, fecha, fuente y resumen de arriba (sin el aviso del calendario)")
func actaEncabezado() {
    let a = LectorActa.interpretar(completa, archivo: "reunion-comite-202611161445.md")
    #expect(a?.id == "reunion-comite-202611161445.md")
    #expect(a?.titulo == "Comité de revisión del contrato")
    #expect(a?.fuente == .dictado && a?.fuente.nombre == "Dictado")
    #expect(a?.fecha == f(16, 14, 45))
    #expect(a?.evento == "Reunión semanal")
    #expect(a?.resumen == "El comité aprobó la nueva cláusula de confidencialidad. Falta que el cliente confirme las fechas.\n\nQuedó pendiente la versión final del anexo.")
}

@Test("Acta: decisiones, tareas con su cita, descartado y el correo sin la cerca")
func actaSecciones() {
    let a = LectorActa.interpretar(completa, archivo: "x.md")
    #expect(a?.decisiones == ["Se usa la plantilla nueva", "El anexo sale el viernes"])
    #expect(a?.tareas.count == 4)   // también entran las de dos partes ("Marta · preparar el acta", "Tú · revisar")
    #expect(a?.cuentaTareas == 3 && a?.tareasMias.map(\.texto) == ["enviar el anexo firmado", "llamar a la notaría", "revisar"])
    let t = a?.tareas.first
    #expect(t?.texto == "enviar el anexo firmado" && t?.cuando == "viernes" && t?.gatillo == "al terminar la revisión")
    #expect(t?.cita == "yo envío el anexo firmado el viernes" && t?.hecha == false && t?.dueno == "Tú")
    #expect(a?.tareas[1].hecha == true && a?.tareas[1].cita == "la llamo mañana a primera hora" && a?.tareas[1].gatillo == nil)
    #expect(a?.tareas[2].dueno == "Marta" && a?.tareas[2].esMia == false)
    #expect(a?.descartado == ["Pedro · mandar el presupuesto", "Tú · revisar (vago)"])
    #expect(a?.correo == "Estimado/a Marta,\n\nQuedamos en enviar el anexo el viernes.\n## Esto no es una sección\nUn saludo.")
}

@Test("Acta de Meet sin secciones: solo resumen; sin correo ni tareas")
func actaMinima() {
    let texto = """
    ---
    date: 2026-11-13T09:30-05:00
    source: meet-notas
    tipo: reunion
    reunion: Llamada con el equipo
    ---

    # Notas · Llamada con el equipo

    Se repasó el calendario de la semana.
    """
    let a = LectorActa.interpretar(texto, archivo: "reunion-llamada.md")
    #expect(a?.fuente == .meet && a?.fuente.nombre == "Meet")
    #expect(a?.resumen == "Se repasó el calendario de la semana.")
    #expect(a?.tareas.isEmpty == true && a?.decisiones.isEmpty == true && a?.descartado.isEmpty == true)
    #expect(a?.correo == nil && a?.evento == nil)
    #expect(a?.cuentaTareas == 0)
}

@Test("Acta sin resumen automático: el aviso no se muestra como resumen")
func actaSinResumen() {
    let texto = """
    ---
    date: 2026-11-13T09:30-05:00
    source: dictado-notas
    reunion: Sin modelo
    ---

    # Notas · Sin modelo

    Sin resumen automático (sin conexión). La transcripción está fuera del cerebro (ver abajo).
    """
    let a = LectorActa.interpretar(texto, archivo: "reunion-sin.md")
    #expect(a?.titulo == "Sin modelo")
    #expect(a?.resumen == "")
}

@Test("Acta: sin frontmatter toma el título del encabezado; basura devuelve nil")
func actaTolerante() {
    let sin = LectorActa.interpretar("# Notas · Idea suelta\n\nUn párrafo.", archivo: "reunion-a.md")
    #expect(sin?.titulo == "Idea suelta" && sin?.fecha == nil && sin?.fuente == .otra && sin?.fuente.nombre == "Notas")
    #expect(LectorActa.interpretar("", archivo: "reunion-b.md") == nil)
    #expect(LectorActa.interpretar("---\nsource: x\n---\n", archivo: "reunion-c.md") == nil)
    // Un frontmatter sin cerrar no rompe nada.
    #expect(LectorActa.interpretar("---\ndate: 2026\n# Notas · Cortada\n", archivo: "reunion-d.md")?.titulo == "Cortada")
}

@Test("Actas: la más reciente primero y las que no traen fecha, al final")
func actasOrden() {
    func acta(_ id: String, _ fecha: Fecha?) -> ActaReunion {
        ActaReunion(id: id, titulo: id, fecha: fecha, fuente: .otra, resumen: "", decisiones: [], tareas: [], descartado: [], correo: nil, evento: nil)
    }
    let orden = LectorActa.ordenar([acta("a", f(10, 9)), acta("sin", nil), acta("c", f(16, 9)), acta("b", f(13, 9))])
    #expect(orden.map(\.id) == ["c", "b", "a", "sin"])
}

@Test("Acta: el cuándo en palabras, con la hora en doce horas")
func actaCuando() {
    let cal = calendarioDePrueba()
    #expect(LectorActa.cuando(f(16, 14, 45), calendario: cal) == "lun 16 nov · 2:45 p. m.")
    #expect(LectorActa.cuando(f(16, 0, 5), calendario: cal) == "lun 16 nov · 12:05 a. m.")
    #expect(LectorActa.cuando(f(16, 12), calendario: cal) == "lun 16 nov · 12:00 p. m.")
    #expect(LectorActa.cuando(nil) == "Sin fecha")
}
