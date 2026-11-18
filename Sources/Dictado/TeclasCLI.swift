import DictadoKit
import Foundation

/// `Dictado --teclas-wav [carpeta]`: escribe los sonidos de cada perfil como WAV (sin abrir ningún dispositivo de audio
/// ni reproducir nada) y mide cada uno: duración, pico, RMS y centroide espectral. Por defecto en /tmp/dictado-teclas.
func renderTeclasWAV(_ carpeta: URL) -> Bool {
    do {
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
    } catch {
        print("no pude crear \(carpeta.path): \(error.localizedDescription)")
        return false
    }
    print("perfil     sonido        dur(ms)  pico   RMS    centroide(Hz)  archivo")
    var ok = true
    for perfil in PerfilTeclas.allCases {
        for (abajo, grande) in [(true, false), (false, false), (true, true), (false, true)] {
            let x = SintesisTeclas.generar(perfil, abajo: abajo, grande: grande)
            let nombre = "\(perfil.rawValue)-\(abajo ? "abajo" : "arriba")\(grande ? "-grande" : "").wav"
            let archivo = carpeta.appendingPathComponent(nombre)
            do { try AnalisisAudio.datosWAV(x).write(to: archivo) } catch { ok = false }
            let pico = AnalisisAudio.pico(x)
            if pico >= 1 { ok = false }
            let etiqueta = "\(abajo ? "abajo" : "arriba")\(grande ? "+grande" : "")"
            let cifras = String(format: "%7.1f  %.3f  %.4f  %10.0f", AnalisisAudio.duracion(x) * 1000, pico,
                                AnalisisAudio.rms(x), AnalisisAudio.centroide(x))
            print(perfil.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0),
                  etiqueta.padding(toLength: 14, withPad: " ", startingAt: 0), cifras, "    ", archivo.path)
        }
    }
    return ok
}
