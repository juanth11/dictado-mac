# Arquitectura

Dos targets en `Package.swift`:

| Target | Qué tiene | Depende de |
|---|---|---|
| `DictadoKit` | Lógica pura, sin SwiftUI ni IOKit: `GeometriaVentanas` (reparto de ventanas), `MapeoHID` (mapeo de Hyper), `Medida` (formato de bytes y porcentajes), `EnlaceClaude` | Foundation, CoreGraphics |
| `Dictado` | La app: vistas, isla, Centro, lectura/escritura del sistema (Accesibilidad, IOKit, hidutil) | `DictadoKit` |
| `DictadoKitTests` | Swift Testing sobre `DictadoKit` | `DictadoKit` |

Regla: lo que se pueda decidir con valores simples (rectángulos, números, texto) va a `DictadoKit` y se prueba con `swift test`; lo que toque el sistema se queda en la app y se prueba con los `--probar-*`.

Tests con solo las Command Line Tools (sin Xcode completo):

```bash
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
swift test -Xswiftc -F -Xswiftc $F -Xlinker -F -Xlinker $F -Xlinker -rpath -Xlinker $F
```

En los archivos de test no se puede hacer `import Foundation` con las CLT (falta `_Testing_Foundation`); con Xcode completo sí.

La isla vive en `Sources/Dictado/VistaIsla.swift` (forma y vista raíz) y siete archivos `Isla*.swift` (Dictado, Volumen, Piezas, Compacta, Expandida, Reproductor, Agenda). Un tipo va junto a la pantalla que lo usa; las piezas compartidas, en `IslaPiezas.swift`.

Pendiente de mover: `Bitacora` y `Escaner` (Salud) dependen de `ItemLimpieza`, un tipo de la app; hay que separar primero ese tipo. Revisión completa: `docs/architecture-review-2026-11-01.md`.
