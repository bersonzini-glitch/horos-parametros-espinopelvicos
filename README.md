# Parámetros espinopélvicos — Horos plugin for Apple Silicon

[Español](#español) · [English](#english)

Native **arm64** plugin for **Horos 4** that measures sagittal spinopelvic alignment on a lateral standing radiograph, in the spirit of Surgimap: **PI, PT, SS, LL, PI−LL, SVA, T1PA and thoracic kyphosis**, with the SRS-Schwab sagittal modifiers.

---

## Español

### Qué mide

| Parámetro | Definición |
|---|---|
| **PI** – Incidencia pélvica | Ángulo entre la perpendicular al platillo de S1 en su punto medio y la línea a los centros de las cabezas femorales |
| **PT** – Tilt pélvico | Ángulo entre la vertical y la línea cabezas femorales – punto medio de S1 |
| **SS** – Slope sacro | Ángulo entre el platillo de S1 y la horizontal |
| **LL** – Lordosis lumbar | Cobb entre el platillo superior de L1 y el de S1 |
| **PI−LL** | Mismatch pelvis-lordosis |
| **TK** – Cifosis torácica | Cobb entre el platillo superior de T4 (o T5) y el inferior de T12 |
| **T1PA** – T1 pelvic angle | Ángulo entre las líneas cabezas femorales–centro de T1 y cabezas femorales–punto medio de S1 |
| **SVA** | Distancia horizontal entre la plomada de C7 y la esquina posterosuperior de S1 |

También muestra los **modificadores SRS-Schwab** de PI−LL, PT y SVA (0 / + / ++).

Convenciones: LL y TK positivos significan lordosis y cifosis. SVA y PT positivos significan hacia anterior. El paciente puede mirar a la izquierda o a la derecha: el plugin detecta la orientación por las esquinas de los platillos.

### Requisitos

- Horos **4.x** en una Mac con Apple Silicon (M1 o posterior).
- macOS 11 o posterior.

### Instalación

1. Descargá **`Instalar Parametros Espinopelvicos.pkg`** desde [Releases](../../releases/latest).
2. Hacé doble clic. Como el instalador no está notarizado por Apple, la Mac puede decir que no puede verificarlo: tocá **OK**, andá a **Ajustes del Sistema → Privacidad y seguridad**, bajá hasta el final y tocá **"Abrir igualmente"**.
3. Seguí el instalador y, al terminar, cerrá y volvé a abrir Horos.

<details>
<summary>Instalación manual con el .zip (usuarios avanzados)</summary>

Descomprimí `SpinopelvicParams.horosplugin.zip`, quitá la cuarentena y copialo a `~/Library/Application Support/Horos/Plugins/`:

```bash
xattr -dr com.apple.quarantine ~/Downloads/SpinopelvicParams.horosplugin
```

Sin ese paso macOS bloquea la carga del plugin.
</details>

### Uso

1. Abrí en el visor una **telerradiografía de columna completa de perfil**, de pie.
2. Menú **Plugins → ROI Tools → Parámetros espinopélvicos…** Se abre un panel con los pasos, y la herramienta de punto queda activa.
3. Hacé clic en la imagen en el orden que pide el panel. Cada clic avanza al paso siguiente:
   1. Centro de la cabeza femoral 1
   2. Centro de la cabeza femoral 2 (opcional; saltalo si se superponen)
   3. S1: esquina posterosuperior y anterosuperior del platillo
   4. L1: esquinas posterior y anterior del platillo superior
   5. T12: esquinas posterior y anterior del platillo inferior (opcional)
   6. T4 o T5: esquinas posterior y anterior del platillo superior (opcional)
   7. Centro del cuerpo de T1 (opcional)
   8. Centro del cuerpo de C7 (opcional)
4. Los resultados y las líneas auxiliares se actualizan en vivo. **Arrastrá cualquier punto para ajustarlo.** También podés elegir un paso en la lista para rehacerlo, o usar **Saltar**, **Borrar punto** y **Reiniciar**.
5. **Copiar resultados** copia el informe al portapapeles para pegarlo en la historia clínica.

Los puntos se guardan con la imagen como ROIs de Horos. Si volvés a abrir el plugin sobre la misma imagen, los recupera.

**Escala del SVA.** Si la imagen trae espaciado de píxel DICOM, el SVA se informa en mm. Si no lo trae (por ejemplo, una foto convertida a DICOM), se informa en píxeles. En ese caso dibujá una línea con la herramienta de longitud de Horos sobre un objeto de tamaño conocido (regla, esfera de calibración, implante), tocá **Calibrar…** e ingresá su medida real. Tené en cuenta que la magnificación radiográfica puede alterar el SVA. Los ángulos no dependen de la escala.

### Compilar desde el código

Solo hacen falta las *Command Line Tools* de Xcode (no Xcode completo):

```bash
xcode-select --install   # si no las tenés
./build.sh               # corre los tests de geometría y genera el plugin, el .zip y el .pkg en build/
```

### Aviso

Herramienta de apoyo para medición. Los valores dependen de dónde se coloquen los puntos y deben ser revisados por el profesional. Este software **no es un dispositivo médico** y se distribuye "tal cual", sin garantía (ver [LICENSE](LICENSE)).

---

## English

### What it measures

| Parameter | Definition |
|---|---|
| **PI** – Pelvic incidence | Angle between the perpendicular to the S1 endplate at its midpoint and the line to the femoral head centers |
| **PT** – Pelvic tilt | Angle between the vertical and the femoral heads – S1 midpoint line |
| **SS** – Sacral slope | Angle between the S1 endplate and the horizontal |
| **LL** – Lumbar lordosis | Cobb angle, L1 superior endplate to S1 endplate |
| **PI−LL** | Pelvic incidence – lumbar lordosis mismatch |
| **TK** – Thoracic kyphosis | Cobb angle, T4 (or T5) superior endplate to T12 inferior endplate |
| **T1PA** – T1 pelvic angle | Angle between femoral heads → T1 center and femoral heads → S1 midpoint |
| **SVA** | Horizontal offset of the C7 plumb line from the posterosuperior corner of S1 |

It also shows the **SRS-Schwab** sagittal modifiers for PI−LL, PT and SVA.

Sign conventions: positive LL and TK mean lordosis and kyphosis. Positive SVA and PT mean anterior. The patient may face either way, since the facing direction is taken from the endplate corners.

### Requirements

- Horos **4.x** on an Apple Silicon Mac (M1 or later).
- macOS 11 or later.

### Install

1. Download **`Instalar Parametros Espinopelvicos.pkg`** from [Releases](../../releases/latest).
2. Double-click it. The installer isn't notarized by Apple, so macOS may say it can't verify it: click **OK**, open **System Settings → Privacy & Security**, scroll down and click **"Open Anyway"**.
3. Follow the installer, then quit and reopen Horos.

<details>
<summary>Manual install from the .zip (advanced)</summary>

Unzip `SpinopelvicParams.horosplugin.zip`, remove the quarantine flag and copy it into `~/Library/Application Support/Horos/Plugins/`:

```bash
xattr -dr com.apple.quarantine ~/Downloads/SpinopelvicParams.horosplugin
```

Without this, macOS refuses to load the plugin.
</details>

### Usage

1. Open a **standing lateral whole-spine radiograph** in the 2D viewer.
2. **Plugins → ROI Tools → Parámetros espinopélvicos…** A floating panel lists the steps, and the point tool is selected.
3. Click each landmark as the panel asks: femoral head centers, the S1, L1, T12 and T4/T5 endplate corners (posterior, then anterior), and the T1 and C7 body centers. Optional steps can be skipped.
4. Results and helper lines update live. Drag any point to adjust it.
5. **Copiar resultados** copies the report to the clipboard.

Landmarks are regular Horos ROIs, so they are saved with the image and picked up again when the plugin is reopened. Without DICOM pixel spacing, SVA is shown in pixels until you calibrate on a length line of known size (**Calibrar…**).

### Building

```bash
./build.sh   # runs the geometry tests, then builds the plugin, the .zip and the .pkg into build/
```

The plugin links against the Horos executable with `-bundle_loader` and declares only the Horos classes it uses (`HorosAPI.h`). Horos 4 is signed with `disable-library-validation`, so an ad-hoc signature is enough.

| File | Purpose |
|---|---|
| `SpinopelvicParams.m` | Plugin entry point, guided panel, landmark capture through Horos ROIs, helper lines |
| `SPMath.c` | Geometry, in pure C (no Horos dependency) |
| `test_math.c` | Synthetic-geometry tests, facing left and right |

### Disclaimer

A measurement aid. Values depend on landmark placement and must be reviewed by the clinician. This software is **not a medical device** and is provided "as is", without warranty (see [LICENSE](LICENSE)).

---

Made by **Bernardo Sonzini Astudillo** — [columna-spine.com](https://columna-spine.com)
