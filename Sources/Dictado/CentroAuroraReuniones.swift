import AppKit
import DictadoKit
import SwiftUI

// Sección Reuniones del Centro: las notas que el sistema ya genera (`reunion-*.md`, de Dictado o de Meet), la más reciente primero. A
// la izquierda la lista; a la derecha la elegida, armada con sus secciones: el resumen grande, tus tareas con su cita, lo descartado
// (cerrado) y el borrador del correo de seguimiento. "Copiar borrador" solo copia el texto: nada se envía desde aquí.

struct ReunionesAurora: View {
    let datos: DatosCentro
    let nav: NavegacionAurora
    let simulado: Bool

    private static let anchoLista: CGFloat = 398

    /// La nota elegida: la que dice la navegación o, si no hay (o desapareció), la primera.
    static func elegida(_ actas: [ActaReunion], _ id: String?) -> ActaReunion? {
        actas.first { $0.id == id } ?? actas.first
    }

    var body: some View {
        let actas = datos.reuniones.actas
        let actual = Self.elegida(actas, nav.reunion)
        HStack(alignment: .top, spacing: AuroraCentro.separacion) {
            lista(actas, actual: actual)
                .frame(width: Self.anchoLista)
            if let actual {
                DetalleActa(acta: actual, nav: nav, simulado: simulado, carpeta: datos.reuniones.carpetaNotas)
            } else {
                vacio
            }
        }
    }

    private func lista(_ actas: [ActaReunion], actual: ActaReunion?) -> some View {
        TarjetaVidrioGrande(alto: nil, relleno: EdgeInsets(top: 16, leading: 10, bottom: 12, trailing: 10)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    RotuloPieza("Reuniones", color: AuroraCentro.suave, grande: true)
                    if !actas.isEmpty { Text("\(actas.count)").font(.system(size: 13, weight: .bold)).foregroundStyle(.white.opacity(0.85)) }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                if !actas.isEmpty { UltimaGrabacionFila(carpetaNotas: datos.reuniones.carpetaNotas).padding(.horizontal, 12) }
                if actas.isEmpty {
                    Text(datos.reuniones.leida ? "Sin notas todavía." : "Buscando tus notas…").font(AuroraCentro.detalle).foregroundStyle(AuroraCentro.suave).padding(.horizontal, 12)
                    Spacer(minLength: 0)
                } else {
                    DesplazableAurora(simulado: simulado) {
                        VStack(spacing: 2) {
                            ForEach(actas) { a in
                                FilaElegibleAurora(elegida: a.id == actual?.id, accion: {
                                    if nav.reunion != a.id { nav.descartadoAbierto = false; nav.correoCopiado = false }
                                    nav.reunion = a.id
                                }) {
                                    FilaActa(acta: a, ahora: datos.reloj.ahora)
                                }
                                .accessibilityLabel("\(a.titulo), \(LectorActa.cuando(a.fecha)), \(a.fuente.nombre), \(a.cuentaTareas) tareas")
                            }
                        }
                    }
                }
            }
        }
    }

    private var vacio: some View {
        TarjetaVidrioGrande(alto: nil) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Aquí van tus reuniones").font(AuroraCentro.titulo)
                Text("Cuando grabes una reunión con Dictado o con Meet, sus notas aparecen solas: el resumen, tus tareas con lo que dijiste y el borrador del correo de seguimiento.")
                    .font(AuroraCentro.detalle).foregroundStyle(AuroraCentro.suave).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }
}

private struct FilaActa: View {
    let acta: ActaReunion
    let ahora: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(acta.titulo).font(.system(size: 17, weight: .semibold)).tracking(-0.15).lineLimit(2).multilineTextAlignment(.leading)
            Text(LectorActa.cuando(acta.fecha)).font(AuroraCentro.detalle).foregroundStyle(AuroraCentro.resumen).lineLimit(1)
            HStack(spacing: 8) {
                Text(acta.fuente.nombre).font(AuroraCentro.minimo).foregroundStyle(AuroraCentro.suave)
                Text("·").foregroundStyle(AuroraCentro.sutil)
                Text(acta.cuentaTareas == 0 ? "sin tareas" : (acta.cuentaTareas == 1 ? "1 tarea" : "\(acta.cuentaTareas) tareas"))
                    .font(AuroraCentro.minimo).foregroundStyle(acta.cuentaTareas == 0 ? AuroraCentro.sutil : AuroraCentro.verdeClaro)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// La nota elegida, con todas sus secciones.
private struct DetalleActa: View {
    let acta: ActaReunion
    let nav: NavegacionAurora
    let simulado: Bool
    let carpeta: URL?

    var body: some View {
        TarjetaVidrioGrande(alto: nil, relleno: EdgeInsets(top: 22, leading: 28, bottom: 18, trailing: 28)) {
            DesplazableAurora(simulado: simulado) {
                VStack(alignment: .leading, spacing: 20) {
                    encabezado
                    resumen
                    if !acta.decisiones.isEmpty { decisiones }
                    tareas
                    if !acta.descartado.isEmpty { descartado }
                    if let correo = acta.correo { borrador(correo) }
                }
                .padding(.trailing, 4)
            }
        }
    }

    private var encabezado: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(acta.titulo).font(AuroraCentro.titulo).tracking(-0.3).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                ChipAurora(texto: LectorActa.cuando(acta.fecha), icono: "calendar")
                ChipAurora(texto: acta.fuente.nombre, icono: acta.fuente == .meet ? "video" : "mic")
                if let evento = acta.evento { ChipAurora(texto: "En el calendario: " + evento) }
            }
            BotonesGrabacion(transcripcion: acta.transcripcion.map { URL(fileURLWithPath: $0) }, nota: carpeta?.appendingPathComponent(acta.id))
        }
    }

    private var resumen: some View {
        Text(acta.resumen.isEmpty ? "Esta nota no trae resumen." : LectorActa.frases(acta.resumen, maximo: 3))
            .font(.system(size: 21, weight: .regular)).tracking(-0.2).lineSpacing(5)
            .foregroundStyle(acta.resumen.isEmpty ? AuroraCentro.suave : Color.white.opacity(0.94))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var decisiones: some View {
        VStack(alignment: .leading, spacing: 8) {
            RotuloPieza("Decisiones", color: AuroraCentro.suave, grande: true)
            ForEach(Array(acta.decisiones.enumerated()), id: \.offset) { _, d in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Circle().fill(Color.white.opacity(0.6)).frame(width: 6, height: 6).offset(y: -2)
                    Text(d).font(.system(size: 16, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var tareas: some View {
        let mias = acta.tareasMias
        return VStack(alignment: .leading, spacing: 12) {
            RotuloPieza(mias.isEmpty ? "Tus tareas" : "Tus tareas · \(mias.count)", color: AuroraCentro.verdeClaro, grande: true)
            if mias.isEmpty {
                Text("Ninguna tarea tuya en esta reunión.").font(AuroraCentro.detalle).foregroundStyle(AuroraCentro.suave)
            }
            ForEach(Array(mias.enumerated()), id: \.offset) { i, t in TarjetaTareaActa(tarea: t, indice: i) }
        }
    }

    private var descartado: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { nav.descartadoAbierto.toggle() } label: {
                HStack(spacing: 8) {
                    Image(systemName: nav.descartadoAbierto ? "chevron.down" : "chevron.right").font(.system(size: 12, weight: .bold)).frame(width: 14)
                    RotuloPieza("Descartado · \(acta.descartado.count)", color: AuroraCentro.suave, grande: true)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PulsadoAurora())
            .foregroundStyle(AuroraCentro.suave)
            .accessibilityLabel("Descartado, \(acta.descartado.count) líneas, " + (nav.descartadoAbierto ? "abierto" : "cerrado"))
            if nav.descartadoAbierto {
                ForEach(Array(acta.descartado.enumerated()), id: \.offset) { _, d in
                    Text(d).font(AuroraCentro.detalle).foregroundStyle(AuroraCentro.suave).fixedSize(horizontal: false, vertical: true).padding(.leading, 24)
                }
            }
        }
    }

    private func borrador(_ correo: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                RotuloPieza("Correo de seguimiento (borrador)", color: AuroraCentro.suave, grande: true)
                Spacer(minLength: 0)
                BotonAura(nav.correoCopiado ? "Copiado" : "Copiar borrador", icono: nav.correoCopiado ? "checkmark" : "doc.on.doc", estilo: .lleno, grande: true,
                          ayuda: "Copiar el texto del borrador (no se envía nada)") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(correo, forType: .string)
                    nav.correoCopiado = true
                    Task { try? await Task.sleep(for: .seconds(1.8)); nav.correoCopiado = false }
                }
            }
            Text(correo).font(.system(size: 15.5, weight: .regular)).lineSpacing(3).foregroundStyle(Color.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background { RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.06)) }
                .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1) }
                .textSelection(.enabled)
        }
    }
}

/// Una tarea tuya: lo que hay que hacer, cuándo, qué la dispara y lo que dijiste (la cita, en cursiva entre comillas).
private struct TarjetaTareaActa: View {
    let tarea: ActaReunion.Tarea
    let indice: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: tarea.hecha ? "checkmark.circle.fill" : "circle").font(.system(size: 16, weight: .medium))
                    .foregroundStyle(tarea.hecha ? AuroraCentro.verdeClaro : Color.white.opacity(0.6))
                Text(tarea.texto.prefix(1).uppercased() + tarea.texto.dropFirst()).font(.system(size: 17, weight: .semibold)).tracking(-0.15).strikethrough(tarea.hecha).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let cuando = tarea.cuando { ChipAurora(texto: cuando, icono: "clock") }
            }
            if let gatillo = tarea.gatillo {
                Text("Si: " + gatillo).font(AuroraCentro.detalle).foregroundStyle(AuroraCentro.resumen).padding(.leading, 28)
            }
            if let cita = tarea.cita {
                Text("«\(cita)»").font(.system(size: 15, weight: .medium).italic()).foregroundStyle(Color.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 28)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.06)) }
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1) }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Ir a la grabación

/// Abrir o mostrar en el Finder lo de una grabación de reunión. `ultima` busca la más reciente y deja al día `ultima.md` y `ultima-notas.md`
/// (la misma lógica de `Dictado --ultima-grabacion`).
enum IrALaGrabacion {
    static func ultima(inbox: URL?) -> UltimaGrabacion.Rutas? { UltimaGrabacion.actualizar(carpeta: NotasReunion.carpeta, inbox: inbox) }

    static func abrir(_ url: URL?) {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Selecciona en el Finder los archivos que existan (la transcripción y la nota juntas, si están en carpetas distintas).
    static func mostrarEnFinder(_ urls: [URL?]) {
        let reales = urls.compactMap { $0 }.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !reales.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(reales)
    }
}

/// Tres botones de una grabación ya transcrita: ir a su transcripción, a sus notas y mostrarlas en el Finder. Los que no tienen archivo se
/// apagan (por ejemplo, una nota de Meet no trae transcripción de Dictado).
struct BotonesGrabacion: View {
    let transcripcion: URL?
    let nota: URL?

    private func hay(_ u: URL?) -> Bool { u.map { FileManager.default.fileExists(atPath: $0.path) } ?? false }

    var body: some View {
        HStack(spacing: 8) {
            BotonAura("Transcripción", icono: "text.alignleft", estilo: .oscuro, grande: true, ayuda: "Abrir la transcripción completa de esta reunión") { IrALaGrabacion.abrir(transcripcion) }
                .disabled(!hay(transcripcion))
            BotonAura("Notas", icono: "doc.text", estilo: .oscuro, grande: true, ayuda: "Abrir la nota de esta reunión") { IrALaGrabacion.abrir(nota) }
                .disabled(!hay(nota))
            BotonAura("Mostrar en el Finder", icono: "folder", estilo: .oscuro, grande: true, ayuda: "Mostrar la transcripción y la nota en el Finder") {
                IrALaGrabacion.mostrarEnFinder([transcripcion, nota])
            }
            .disabled(!hay(transcripcion) && !hay(nota))
            Spacer(minLength: 0)
        }
    }
}

/// En la lista: lo mismo para la última grabación, sin tener que buscarla (busca al tocar).
struct UltimaGrabacionFila: View {
    let carpetaNotas: URL?

    var body: some View {
        HStack(spacing: 6) {
            Text("Última grabación").font(AuroraCentro.minimo).foregroundStyle(AuroraCentro.suave).lineLimit(1)
            Spacer(minLength: 0)
            BotonAura(icono: "text.alignleft", estilo: .oscuro, redondo: true, compacto: true, ayuda: "Abrir la transcripción de la última grabación") {
                IrALaGrabacion.abrir(IrALaGrabacion.ultima(inbox: carpetaNotas)?.transcripcion.map { URL(fileURLWithPath: $0) })
            }
            BotonAura(icono: "doc.text", estilo: .oscuro, redondo: true, compacto: true, ayuda: "Abrir la nota de la última grabación") {
                IrALaGrabacion.abrir(IrALaGrabacion.ultima(inbox: carpetaNotas)?.notas.map { URL(fileURLWithPath: $0) })
            }
            BotonAura(icono: "folder", estilo: .oscuro, redondo: true, compacto: true, ayuda: "Mostrar la última grabación en el Finder") {
                let r = IrALaGrabacion.ultima(inbox: carpetaNotas)
                IrALaGrabacion.mostrarEnFinder([r?.transcripcion, r?.notas].map { $0.map { URL(fileURLWithPath: $0) } })
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }
}
