# SPI ISP Admin API (.NET 8)

Esta carpeta contiene la API REST corporativa de aprovisionamiento de red del ISP, completamente desarrollada en **.NET 8 (C#)** con conexión de alto rendimiento a PostgreSQL utilizando **Npgsql**.

## 📁 Archivos Clave del Microservicio
* `Program.cs`: Inicializador del servidor web, pool de conexiones a Postgres y Swagger docs.
* `smi-api.csproj`: Archivo de proyecto con paquetes NuGet.
* `Dockerfile`: Compilación optimizada en múltiples etapas para entornos de producción.
* `Controllers/`:
  - `ClientesController.cs`: Registro de abonados (Altas).
  - `EquiposController.cs`: Registro de módems/ONUs en inventario con formateo MAC.
  - `RedController.cs`: Configuración física de CMTS, subredes CIDR y pools de red.
  - `ServiciosController.cs`: **Control del Ciclo de Vida del Servicio (Altas, Suspensiones, Reactivaciones y Bajas)** con validación de ruteo IP.

*Nota: Los antiguos archivos `main.py` y `requirements.txt` de la versión previa en Python pueden ser eliminados con seguridad de este directorio, ya que el contenedor compila y corre exclusivamente utilizando C#.*
