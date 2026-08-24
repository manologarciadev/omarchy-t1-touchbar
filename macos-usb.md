# Crear un USB booteable macOS desde Linux

Esta guía cubre cómo generar un USB de instalación macOS **directamente desde Omarchy / Arch**, sin otra Mac. Necesario para inicializar el firmware del chip T1 (ver `README.md §Prerrequisito crítico`).

---

## TL;DR — Monterey en un USB

```bash
# 1. Descargar BaseSystem.dmg desde los servidores de Apple
git clone --depth=1 --recursive https://github.com/kholia/OSX-KVM.git
cd OSX-KVM
python3 fetch-macOS-v2.py   # elegir opción 5 (Monterey 12.6)

# 2. Compilar dmg2img (no está en repos oficiales)
curl -sLO https://archive.ubuntu.com/ubuntu/pool/universe/d/dmg2img/dmg2img_1.6.7+git20201227.a3e4134.orig.tar.xz
tar xf dmg2img_1.6.7+git20201227.a3e4134.orig.tar.xz
cd dmg2img-1.6.7+git20201227.a3e4134 && make && cd ..

# 3. Convertir DMG → IMG raw (HFS+)
./dmg2img-1.6.7+git20201227.a3e4134/dmg2img OSX-KVM/BaseSystem.dmg BaseSystem.img

# 4. Grabar al USB (⚠️ reemplaza /dev/sdX, desmonta primero)
lsblk   # identificar el USB
sudo dd if=BaseSystem.img of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

---

## Paso a paso detallado

### 1. Elegir versión de macOS

| Modelo | Última soportada | fetch-macOS opción |
|---|---|---|
| MacBookPro13,1 (13" 2016, no TB) | Monterey 12 | 5 |
| MacBookPro13,2 (13" 2016 TB) | Monterey 12 | 5 |
| MacBookPro13,3 (15" 2016 TB) | Monterey 12 | 5 |
| MacBookPro14,2 (13" 2017 TB) | Monterey 12 | 5 |
| MacBookPro14,3 (15" 2017 TB) | Monterey 12 | 5 |

Monterey (opción 5) también funciona y es más ligero (~3 GB IMG vs ~5 GB). Si no te importa la versión, Monterey es más rápido de descargar.

### 2. Verificar el DMG

El `chunklist` interno puede fallar la verificación con `Inappropriate ioctl` (no hay TTY interactivo). Si el archivo termina con `Download complete!` y tiene el tamaño esperado (`623.5 MB` para Monterey), es válido.

### 3. Convertir con dmg2img

Salida esperada:

```
opening partition 5 ...                    100.00%  ok
opening partition 6 ...                    100.00%  ok
...
Archive successfully decompressed as BaseSystem.img
```

Tamaño final: ~3.0 GB HFS+ raw.

### 4. Grabar al USB

⚠️ **Importante:**
- El USB debe ser **≥ 4 GB**.
- **Desmonta** las particiones del USB antes: `sudo umount /dev/sdX*`.
- Reemplaza `/dev/sdX` por el dispositivo correcto (verifica con `lsblk` — debe coincidir con tu USB, no con el SSD interno).
- `dd` borra todo el contenido del USB.

Si grabas disco entero (recomendado, `of=/dev/sdX`):
- El firmware del Mac detecta la partición HFS+ automáticamente y la bootea.
- Si tu USB es más grande que la imagen (ej. 16 GB), el resto queda sin asignar — el Mac no se queja.

Si grabas una partición (`of=/dev/sdX1`):
- Requiere tabla de particiones GPT preexistente con tipo Apple HFS+ en esa partición.
- ⚠️ Más propenso a fallos de boot — el método de disco entero es más robusto.

### 5. Arrancar el Mac

1. Conecta el USB.
2. Apaga la Mac.
3. Enciende manteniendo **Opción (⌥)** hasta ver el selector de arranque.
4. Selecciona el volumen **EFI Boot** o **macOS Base System** (icono naranja).
5. Si arranca en macOS Recovery: conecta a Wi-Fi cuando lo pida.

### 6. Instalar macOS

1. Abre **Utilidad de Discos**.
2. Menú *Visión* → *"Mostrar todos los dispositivos"*.
3. Selecciona **el disco externo o interno donde quieras instalar** (NO toques el SSD interno del sistema si tienes archivos importantes).
4. Botón **Borrar** → Nombre: `MacintoshHD` → Formato: **APFS** → Esquema: **GUID** → Borrar.
5. Sal de Utilidad de Discos.
6. Menú **Reinstalar macOS** → selecciona `MacintoshHD`.
7. Espera: descarga ~12 GB + instalación. Puede reiniciar varias veces.
   - Si vuelve a Omarchy en medio, apaga, enciende con ⌥ y elige `MacintoshHD` para continuar.
8. **Llega al escritorio** (no basta con el picker de Recovery).
9. Espera 1 minuto completo.
10. Menú  → **Apagar** (no reiniciar, no entrar a Recovery después).

### 7. Volver a Omarchy

Enciende normal. El T1 debería aparecer como `05ac:8600 iBridge` ahora.

```bash
lsusb -d 05ac:
# Esperado: Apple, Inc. iBridge
```

Si sigues viendo `05ac:1281 Apple Mobile Device (Recovery Mode)`, repite el flujo de macOS pero asegúrate de llegar al escritorio y apagar bien.

---

## Troubleshooting

### El USB no aparece en el selector de arranque (⌥)

- Verifica que el Mac arrancó desde EFI (no Legacy BIOS) — los Mac 2016+ usan EFI siempre.
- Regraba el USB con `dd` disco entero.
- Prueba otro puerto USB (algunos hubs no funcionan en boot).

### macOS Recovery pide un "Recovery ID" o se queda cargando

Necesita internet. Conecta Wi-Fi o usa el adaptador USB Ethernet.

### macOS dice "No se puede instalar en este disco"

El disco destino debe ser APFS + GUID. Borra con Utilidad de Discos primero.

### Tras instalar, `lsusb` sigue mostrando `05ac:1281`

- No llegaste al escritorio (te quedaste en el picker de Recovery).
- O apagaste con **⌘+Q** o reiniciar en lugar de Apagar.
- Solución: arranca macOS, llega al escritorio, espera 1 minuto, Apagar correctamente.

---

## Tiempos aproximados

| Paso | Tiempo |
|---|---|
| Descarga BaseSystem.dmg | 5–15 min |
| Conversión dmg → img | 1–2 min |
| Grabación al USB | 1–3 min |
| Descarga macOS en recovery | 20–60 min |
| Instalación | 15–30 min |
| **Total** | **~1 hora** |