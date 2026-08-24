# T1 Touch Bar driver for Omarchy / Arch Linux

[![License: GPL-2.0](https://img.shields.io/badge/License-GPL--2.0-blue.svg)](./LICENSE)
[![Kernel: 6.x+](https://img.shields.io/badge/kernel-6.x%2B-blue)](https://www.kernel.org)
[![Tested: MacBookPro13,2](https://img.shields.io/badge/tested-MacBookPro13,2-lightgrey)](#)

Activa la **Touch Bar** (teclas Esc, F1–F12, brillo, volumen, sensor de luz) en MacBook Pro 13,x / 14,x con chip **T1** corriendo Omarchy o Arch Linux.

---

## ¿Para quién es esto?

| Hardware | Chip | Estado |
|---|---|---|
| MacBook Pro 13" / 15" **2016–2017** (Touch Bar) | **T1** | ✅ Este driver |
| MacBook Pro 2018+ (Touch Bar) | T2 | ❌ Usa [t2linux.org](https://wiki.t2linux.org/) (mejor soporte) |
| MacBook Pro 2016–2017 **sin** Touch Bar | ninguno | ❌ No aplica |

Si tienes un T2 (2018+), el soporte upstream es mucho mejor: `tiny-dfr` funciona, las teclas nativas también, hay tutoriales detallados.

Si tienes un T1, sigue leyendo — sin este driver la Touch Bar está muerta y no tienes tecla **Esc** física ni **F1–F12**.

---

## ⚠️ Prerrequisito crítico

El chip T1 viene de fábrica en modo "Recovery" (`05ac:1281 "Apple Mobile Device (Recovery Mode)"`). **Ningún driver Linux lo reconocerá así.**

Para sacarlo de recovery, hay que **arrancar un macOS completo una vez** (llegar al escritorio). El instalador detectará esto y se negará a continuar si no se ha hecho.

### Cómo inicializar el T1 (sin otra Mac)

El script detallado en [`macos-usb.md`](./macos-usb.md). Resumen:

1. Desde Linux, descarga `BaseSystem.dmg` de Monterey con `fetch-macOS-v2.py` (herramienta de OSX-KVM).
2. Convierte a disco crudo con `dmg2img` (compílalo localmente, no está en repos).
3. Graba a USB con `dd` (ver [`macos-usb.md`](./macos-usb.md) para detalle).
4. Arranca con tecla **Opción (⌥)** → selecciona el USB.
5. En el Recovery de macOS: borra un disco externo como **APFS / GUID**.
6. Reinstala macOS sobre ese disco.
7. **Llega al escritorio** (no basta con el picker de Recovery).
8. Espera 1 minuto. Menú → **Apagar**.
9. Arranca Omarchy. Verifica: `lsusb -d 05ac:` debe mostrar **`iBridge` (05ac:8600)**.

---

## 🚀 Instalación

### Requisitos

Obligatorios (los pide `install.sh`):
- `base-devel` (gcc, make, git)
- `dkms` — para recompilación automática ante updates de kernel
- `linux-headers` (o el paquete de headers de tu kernel)

Recomendados:
- `usbutils` — provee `lsusb`. No es obligatorio (el script cae a `/sys/bus/usb/` si falta) pero útil para verificar tras reboot.

### Pasos

```bash
git clone https://github.com/manologarciadev/omarchy-t1-touchbar.git
cd omarchy-t1-touchbar
sudo ./install.sh
sudo reboot
```

El script:
- Verifica que el iBridge está visible (`05ac:8600`)
- Quita `apple-ib-drv-dkms-git` si está (es para T2)
- Clona [`parport0/mbp-t1-touchbar-driver`](https://github.com/parport0/mbp-t1-touchbar-driver) y lo registra con **DKMS** en `/usr/src/mbp-t1-touchbar-0.1/`
- Compila e instala los módulos para tu kernel actual
- Blacklistea `hid_sensor_hub` (secuestra la 2ª interfaz)
- Configura módulos al boot + udev para re-empuje

### Actualizaciones de kernel (importante)

El driver se compila contra los headers del kernel actual. Hay **dos mecanismos** que cubren esto:

1. **Hook de pacman** (`/usr/share/libalpm/hooks/70-dkms-install.hook`): si haces `pacman -Syu linux linux-headers` mientras el módulo DKMS ya está registrado, recompila automáticamente para el nuevo kernel.
2. **Servicio systemd** (`dkms-autoinstall.service`, habilitado por install.sh): corre `dkms autoinstall` en cada boot como red de seguridad, por si hay race condition entre `pacman -Syu` y `reboot` (caso real: el módulo se registró DESPUÉS del upgrade pero antes del reboot, así el hook de pacman no lo vio).

Si por alguna razón ambos fallaran, fuerza manualmente:

```bash
sudo dkms autoinstall
sudo depmod -a
sudo reboot
```

Verifica el estado DKMS con:

```bash
dkms status mbp-t1-touchbar
# mbp-t1-touchbar/0.1, 7.2.3-arch1-3, x86_64: installed
```

### Desinstalar

```bash
sudo ./install.sh uninstall
sudo reboot
```

---

## ✅ Verificar tras reboot

```bash
lsmod | grep apple_ib
# apple_ibridge        apple_ib_tb        apple_ib_als

ls /sys/bus/hid/drivers/apple-ibridge-hid/0003:05AC:8600.*
# 0003:05AC:8600.0001   (touch / ALS)
# 0003:05AC:8600.0002   (keys)

cat /sys/module/hid_sensor_hub 2>/dev/null && echo "PROBLEMA: blacklist no aplicó" || echo "✓"
```

---

## 🩺 Troubleshooting

<details>
<summary><b>El instalador dice que no detecta 05ac:8600</b></summary>

El firmware del T1 no se inicializó. Repite el flujo de macOS (sección de Prerrequisito crítico).

Verifica con `lsusb -d 05ac:` — debería mostrar `iBridge` y no `Apple Mobile Device (Recovery Mode)`.
</details>

<details>
<summary><b>Tras instalar veo <code>apple_touchbar</code> y <code>apple_ibridge</code> en vez de <code>apple_ib_*</code></b></summary>

Tienes el driver **T2** (`t2linux/apple-ib-drv`) en lugar de T1. Ejecuta:

```bash
sudo pacman -Rns apple-ib-drv-dkms-git
sudo ./install.sh
sudo reboot
```
</details>

<details>
<summary><b>La Touch Bar no responde tras suspend/resume</b></summary>

```bash
sudo modprobe -r apple_ib_tb apple_ib_als apple_ibridge
sudo modprobe apple-ibridge apple-ib-tb apple-ib-als
```

Si persiste, revisa `sudo dmesg | grep -i apple`.
</details>

<details>
<summary><b>La pantalla de la Touch Bar queda apagada</b></summary>

**Es esperado en T1.** `appletbdrm` (el driver DRM del kernel) es **solo-T2**. No hay renderer DRM para T1 todavía. La barra solo muestra la fila de teclas (Esc+F1–F12) en negro, sin gráficos custom como en T2 con `tiny-dfr`.
</details>

<details>
<summary><b>La Touch Bar dejó de funcionar tras <code>pacman -Syu</code> (kernel actualizado)</b></summary>

El hook de pacman + el servicio systemd `dkms-autoinstall` deberían haber recompilado los módulos. Verifica:

```bash
dkms status mbp-t1-touchbar
uname -r
systemctl status dkms-autoinstall.service
```

Si el kernel actual no aparece en la lista de `dkms status`, fuerza la recompilación:

```bash
sudo dkms autoinstall
sudo depmod -a
sudo reboot
```

Si el driver upstream rompió con un cambio de API del kernel, abre un issue en [`parport0/mbp-t1-touchbar-driver`](https://github.com/parport0/mbp-t1-touchbar-driver/issues) con la salida de `dkms build` y `uname -r`.
</details>

<details>
<summary><b>El driver no compila contra mi kernel</b></summary>

El repo upstream está actualizado para kernel ~6.8. Si tienes un kernel más nuevo y hay roturas de API, abre un issue en [`parport0/mbp-t1-touchbar-driver`](https://github.com/parport0/mbp-t1-touchbar-driver/issues) con el error exacto.
</details>

---

## 🔧 Personalizar

### Cambiar modo de la Touch Bar

El driver expone un atributo `mode` por sub-device:

```bash
find /sys/bus/hid/drivers/apple-ib-tb -name mode
echo 1 | sudo tee /sys/bus/hid/drivers/apple-ib-tb/<dev>/mode
```

| Mode | Significado |
|------|-------------|
| 0 | Esc only |
| 1 | Esc + F1–F12 |
| 2 | Esc + special (brillo, vol, media) |
| 3 | Off |

El path cambia cada boot; no hay forma limpia de persistir.

### Si tu layout es ISO español

Por defecto el driver envía `code:49` para F-keys y eventos estándar para Esc. La barra funciona sin remapeos de Hyprland. Si prefieres mapear otras teclas físicas como F-keys, edita `~/.config/hypr/bindings.lua`.

---

## 📚 Referencias

- [`parport0/mbp-t1-touchbar-driver`](https://github.com/parport0/mbp-t1-touchbar-driver) — driver T1 actualizado (Ronald Tschalär original)
- [`michaelahess/macbook-pro-t1-touchbar-linux`](https://github.com/michaelahess/macbook-pro-t1-touchbar-linux) — research sobre el bug de `hid_sensor_hub` en kernel 6.3+
- [`kholia/OSX-KVM`](https://github.com/kholia/OSX-KVM) — `fetch-macOS-v2.py`
- [`im0x/Linux-macOS-Recovery-USB-Creator`](https://github.com/im0x/Linux-macOS-Recovery-USB-Creator) — referencia del método para crear USB macOS desde Linux
- ArchWiki: [MacBookPro13,x](https://wiki.archlinux.org/title/Mac)

---

## 🤝 Contribuir

Issues y PRs bienvenidos. Por favor:

1. Especifica modelo (`cat /sys/class/dmi/id/board_name`) y kernel (`uname -r`).
2. Adjunta `dkms status`, `lsusb -d 05ac: -v`, `lsmod | grep apple_ib` y `sudo dmesg | grep -i apple`.
3. Si es un fallo de compilación DKMS, incluye la salida completa de `dkms build`.

---

## 📄 Licencia

GPL-2.0. Ver [LICENSE](./LICENSE). El driver subyacente (`parport0/mbp-t1-touchbar-driver`) es GPL-2.0 de Ronald Tschalär.