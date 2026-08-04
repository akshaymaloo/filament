

<p align="center">
  <img src="docs/icon.png" width="128" alt="Icono de la aplicación Filament">
</p>

<h1 align="center">Filament</h1>

<p align="center">
  Una aplicación nativa de Quick Look para macOS para archivos de impresión 3D y modelos 3D.<br>
  Selecciona un archivo en Finder, presiona <b>Espacio</b> y obtén una vista previa interactiva en 3D: sin necesidad de un slicer.
</p>

<p align="center">
  <a href="https://ko-fi.com/akshaymaloo"><img src="https://img.shields.io/badge/Ko--fi-Support%20development-FF5E5B?logo=ko-fi&logoColor=white" alt="Apoya el desarrollo en Ko-fi"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="Licencia MIT">
</p>

---

<p align="center">
  <img src="docs/color-preview.gif" width="60%" alt="Vista previa 3MF a todo color interactiva girando en Filament">
</p>
<p align="center"><sub>Los modelos 3MF multimaterial se renderizan con sus colores reales de filamento, con una vista previa interactiva de mesa giratoria renderizada por la extensión de Quick Look de Filament.</sub></p>

### En acción

Presiona <b>Espacio</b> en Finder para obtener una vista previa de cualquier archivo compatible, alterna entre color completo y un aspecto neutro de estudio, y gira alrededor del modelo; luego ábrelo en pantalla completa en la aplicación.

<p align="center">
  <img src="docs/demo.gif" width="80%" alt="Vista previa de archivos 3MF y STL en Finder con Quick Look, alternando color y abriendo en la aplicación Filament">
</p>

Filament añade **miniaturas** y **vistas previas interactivas de Quick Look** para:

- **`.3mf`** — Formato de Manufactura 3D, incluidos archivos de proyecto de Bambu Studio / OrcaSlicer (con múltiples placas, miniaturas de placas incrustadas, estadísticas de impresión y la **Extensión de Producción** de 3MF donde la geometría reside en partes externas del modelo).
- **`.stl`** — binario y ASCII.
- **`.obj`** — Wavefront OBJ.
- **`.ply`** — ASCII y binario (little/big endian).

## Características

- **Miniaturas instantáneas en Finder.** Para 3MF, se usa la imagen de placa incrustada por el slicer para un icono casi instantáneo; STL/OBJ/PLY se renderizan sobre la marcha.
- **Vista previa interactiva.** Presiona Espacio en Finder para una vista previa de SceneKit con órbita, desplazamiento y zoom, con iluminación suave de estudio.
- **Multimaterial a todo color.** Los modelos 3MF de Bambu/Orca pintados con múltiples filamentos se renderizan con sus colores reales del slicer; alterna entre color y un aspecto monocromático neutro de estudio.
- **Explora todas las placas de construcción.** Los proyectos 3MF con múltiples placas obtienen un selector de placas.
- **Información del modelo.** Dimensiones (W × D × H mm) y cantidad de triángulos; tiempo de impresión, peso e impresora para 3MF.
- **Abrir en la aplicación.** Haz doble clic en un archivo compatible (o arrastra y suelta) para abrirlo en la ventana de Filament. Arrastra otro archivo para cambiar el modelo al instante.
- **Rápido con modelos grandes.** Un analizador 3MF de flujo dedicado abre archivos de millones de triángulos en aproximadamente un segundo.
- **Atajos de teclado.** Abrir (⌘O), Recargar (⌘R), Revelar en Finder (⇧⌘R) y Cerrar archivo (⌘W).
- **Abre por defecto.** `install.sh` establece Filament como la aplicación predeterminada para `.3mf` y `.stl` (reemplazando Vista Previa para STL); desactívalo con `--no-defaults`.
- **Respetuoso con la privacidad y fuera de línea.** Todo se ejecuta localmente: sin red, sin telemetría.

## Requisitos

- **macOS 14.0 (Sonoma) o posterior.**
- Para compilar: **Xcode 15 o posterior** y **[XcodeGen](https://github.com/yonaskolb/XcodeGen)**
  (`brew install xcodegen`).
- Para ejecutar las extensiones de Quick Look en Finder debes **firmar** la aplicación (una Apple ID gratuita funciona — ver más abajo).

## Compilación e instalación

### Instalación rápida (un solo comando)

```bash
git clone https://github.com/<your-org-or-user>/filament.git
cd filament
./install.sh
```

`install.sh` verifica los prerrequisitos (Xcode y XcodeGen — instalados vía Homebrew si es necesario), genera el proyecto de Xcode, compila una versión Release, **lo firma para ejecución local** (no se requiere cuenta de Apple Developer), lo instala en
`~/Applications` y registra las extensiones de Quick Look. Para compilar y firmar con tu propio equipo de Apple Developer en su lugar, pasa `DEVELOPMENT_TEAM`:

```bash
DEVELOPMENT_TEAM=ABCDE12345 ./install.sh
```

Desinstala en cualquier momento con `./install.sh --uninstall`.

> Si las vistas previas con la barra espaciadora no aparecen justo después de instalar, cierra y vuelve a iniciar sesión una vez para que Finder recargue las extensiones de Quick Look.

### Compilar en Xcode (manual)

El proyecto de Xcode se genera desde `project.yml` mediante XcodeGen (no está incluido en el repositorio), por lo que el primer paso es generarlo siempre.

#### 1. Clonar y generar el proyecto

```bash
git clone https://github.com/<your-org-or-user>/filament.git
cd filament
brew install xcodegen      # si no lo tienes
xcodegen generate          # crea Filament.xcodeproj
open Filament.xcodeproj
```

#### 2. Establecer un equipo de firma

macOS solo carga una **extensión de aplicación de Quick Look** si la aplicación contenedora está firmada y registrada en Launch Services. En Xcode:

1. Selecciona el proyecto **Filament** en el navegador.
2. Para **cada** uno de los tres objetivos — `Filament`, `ThumbnailExtension`,
   `PreviewExtension` — abre **Firma y Capacidades** y selecciona tu
   **Equipo**. La firma está preconfigurada como *Automática*; solo debes elegir el equipo.
   - No se requiere una cuenta de pago de Apple Developer: iniciar sesión en Xcode con una
     Apple ID gratuita te da un **Equipo Personal** que funciona para uso local.
   - Alternativamente, configura el certificado de firma en **“Firmar para ejecutar localmente”**
     (ad-hoc) para ejecutarlo en tu propio Mac sin ninguna Apple ID.

El prefijo del identificador de paquete es `com.filament3d` (p. ej.
`com.filament3d.Filament`). Cámbialo por tu propio identificador DNS inverso si planeas distribuir la aplicación.

#### 3. Compilar y ejecutar una vez

Compila y ejecuta el objetivo de la aplicación **Filament** (⌘R) al menos una vez. Lanzar la aplicación registra sus extensiones de Quick Look incrustadas en el sistema.

Para una integración en Finder a nivel del sistema, mueve la aplicación compilada a `/Applications` (o
`~/Applications`) y lánzala una vez desde allí.

#### 4. Verificar Quick Look

```bash
# Reinicia el daemon de Quick Look para que recoja las extensiones recién registradas
qlmanage -r
qlmanage -r cache

# Confirma que las extensiones están registradas
pluginkit -m | grep -i filament
```

Luego selecciona un archivo `.3mf`, `.stl`, `.obj` o `.ply` en Finder y presiona
**Espacio** para la vista previa, o visualízalo en una ventana de vista de iconos para la miniatura.

## Compilación por línea de comandos (CI / sin firma)

Para verificar que la aplicación y ambas extensiones se compilan y enlazan **sin** una identidad de firma (p. ej., en un ejecutor de CI):

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild build \
  -project Filament.xcodeproj -scheme Filament \
  -destination 'platform=macOS' -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
```

Compilar el esquema `Filament` también compila ambas extensiones incrustadas (son dependencias del objetivo). Esto produce un `.app` sin firma apto solo para verificación de compilación/enlace: no registrará sus extensiones de Quick Look a nivel del sistema.

## Desarrollo

`ThreeMFKit` es un paquete Swift sin dependencias y puede compilarse y probarse únicamente con la herramienta Swift:

```bash
swift build                 # compila la biblioteca
swift run three-mf-validate #套件 de validación autocontenido (no se necesita XCTest)
swift test                  #套件 de pruebas XCTest (requiere la herramienta Xcode completa)
```

## Arquitectura

- **`ThreeMFKit`** (`Sources/ThreeMFKit`) — núcleo sin dependencias: lector ZIP de solo lectura (vía el framework `Compression`), análisis XML de OPC / 3MF incluida la Extensión de Producción, análisis de mallas STL/OBJ/PLY, una fachada `ModelLoader` que distribuye por tipo de archivo, extracción de placas/miniaturas/estadísticas y construcción de escenas SceneKit (`ModelSCNView`, cámaras, iluminación, sombras).
- **`Filament`** (`App/Filament`) — la aplicación host de SwiftUI. Abre o recibe por arrastre un archivo de modelo y explora las placas de construcción de forma interactiva. Declara el UTI personalizado `com.filament3d.3mf` e incrusta ambas extensiones de Quick Look.
- **`ThumbnailExtension`** (`Extensions/ThumbnailExtension`) — una extensión de aplicación `QLThumbnailProvider` para miniaturas de Finder/Spotlight.
- **`PreviewExtension`** (`Extensions/PreviewExtension`) — una extensión de aplicación `QLPreviewingController` para el panel completo de vista previa con barra espaciadora.

### Identificadores de Tipo Uniforme

- `com.filament3d.3mf` — tipo importado personalizado para `.3mf` (cumple con `public.data` y `public.3d-content`, MIME `model/3mf`).
- STL/OBJ/PLY usan los tipos declarados por el sistema `public.standard-tesselated-geometry-format`,
  `public.geometry-definition-format` y `public.polygon-file-format`.

## Contribuciones

Las issues y pull requests son bienvenidas. Por favor, mantén `ThreeMFKit` sin dependencias y asegúrate de que `swift run three-mf-validate` y `swift build` pasen antes de abrir un PR (CI ejecuta esto más una compilación de Xcode en cada push).

## Soporte

Filament es gratuita y de código abierto. Si la encuentras útil, puedes apoyar su desarrollo:

<a href="https://ko-fi.com/akshaymaloo"><img src="https://ko-fi.com/img/githubbutton_sm.svg" alt="Apóyame en Ko-fi" height="36"></a>

Hoy la aplicación está **firmada de forma ad hoc "para ejecución local"**, por lo que debes compilarla tú mismo con `install.sh`. Las donaciones van destinadas a una membresía del **Apple Developer Program** para que futuras versiones puedan ser **notarizadas**: sin advertencias de Gatekeeper y descargas listas para ejecutar; y, eventualmente, publicadas en la **Mac App Store**. ¡Gracias! 🙏

## Licencia

Publicada bajo la [Licencia MIT](LICENSE).
