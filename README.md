# 🚀 Servidor FTPS para Backups de VCSA (Ubuntu 24.04)

## 🎯 Resumen Ejecutivo

Este documento describe la implementación de un **repositorio FTPS
seguro** en Ubuntu 24.04 para almacenar **copias de seguridad basadas en
archivos de VMware vCenter Server Appliance (VCSA)**.\
Se han seguido las **mejores prácticas de VMware**, garantizando
**seguridad, compatibilidad y estabilidad operativa**.

------------------------------------------------------------------------

## 🔑 Puntos Clave

-   **Puerto estándar FTP (21)** con **TLS explícito (AUTH TLS)**.
-   **Usuario dedicado** (`vcsa-backup`) restringido a su directorio.
-   **Certificado autofirmado** (RSA 4096, CN personalizable).
-   **Modo pasivo** con rango `40000-40100` para compatibilidad con firewall/NAT.
-   **Script automatizado** que instala, configura y valida el servicio.
-   **Registros de auditoría** en `/var/log/vsftpd.log`.

------------------------------------------------------------------------

## ⚙️ Despliegue

1.  Ejecutar el script de automatización en Ubuntu 24.04.
2.  El script instala dependencias, crea un usuario seguro, configura FTPS y valida la conectividad.
3.  Ruta de backup para VCSA:
        ftps://<IP-o-FQDN-del-servidor>/backups
4.  Credenciales para VCSA:
    -   **Usuario:** `vcsa-backup`
    -   **Contraseña:** definida durante la ejecución del script.

------------------------------------------------------------------------
## 📡 Execución en terminal

```console
ssh user@ftp.home
--- en el servidor ---
vim setup-vcsa-ftps.sh
-- se copia el script y se guarda --
chmod +x setup-vcsa-ftps.sh
sudo ./setup-vcsa-ftps.sh
- opcional -
export PASV_ADDR="ftp.home"
export CERT_CN="ftp.home"
```

------------------------------------------------------------------------

## 🛡️ Consideraciones de Seguridad

-   Usuario configurado con shell `nologin` para prevenir accesos interactivos.
-   Integración PAM con autenticación contra `/etc/shadow`.
-   TLS obligatorio para todas las conexiones.
-   Registros completos de autenticación y transferencias en `/var/log/vsftpd.log`.

------------------------------------------------------------------------

## ✅ Integración con VMware VCSA

-   Configurar Backup en VAMI (`https://<vcenter>:5480`).
-   Definir repositorio como:\`ftps://<IP-o-FQDN>/backups`
-   Proporcionar credenciales (`vcsa-backup` + contraseña).
-   Programar backups automáticos (ejemplo: semanal, 23:59).

------------------------------------------------------------------------

## 📊 Beneficios

-   **Seguro**: cifrado TLS, repositorio restringido por usuario.
-   **Confiable**: alineado con la documentación oficial de VMware.
-   **Eficiente**: despliegue automatizado y probado end-to-end.
-   **Auditable**: registros centralizados para operaciones y cumplimiento.

------------------------------------------------------------------------

## 📌 Notas Finales

Esta solución proporciona un **repositorio FTPS listo para producción** para respaldos de VCSA.
Garantiza la **continuidad del negocio** mientras cumple con las **mejores prácticas de seguridad y confiabilidad**.
