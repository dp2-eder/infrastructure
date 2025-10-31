## Pendientes DevOps

Este documento resume las tareas pendientes y acuerdos del área de DevOps a partir de la reunión del **30/10**. Se presenta en un formato limpio y profesional, apto para un archivo `README.md` en GitHub.

---

### 📝 Revisión de Arquitectura (30/10)

Se detallaron los siguientes puntos sobre la arquitectura propuesta:

* **Almacenamiento (Storage):** El servidor de almacenamiento alojará un **file storage** con las imágenes de los platos. Este almacenamiento será **montado como un directorio** en el servidor que aloje el *backend/frontend*.
* **Mecanismo de Invocación (Scrapper):** El *scrapper* podrá ser invocado de dos formas:
    * Mediante un **cronjob** (programado).
    * **A demanda** desde la capa *Core* a través de **RabbitMQ**.
* **Infraestructura (Servidores):** Se solicitó un total de **7 servidores** distribuidos de la siguiente manera para garantizar la **Alta Disponibilidad (HA)**:
    * 2 Servidores para la capa de **Balanceador** (HA).
    * 2 Servidores para las capas de **Frontend y Backend** (Core) (HA).
    * 2 Servidores para **RPA y Scrapper** (HA).
    * 1 Servidor consolidado para **Base de Datos (MySQL), RabbitMQ y File Storage**.
* **Despliegue de Componentes:** Los componentes *backend*, *frontend*, *reverse proxy*, *rpa* y *scrapper* se desplegarán como **contenedores (Docker)**.
* **Orquestación Local:** Se utilizará un archivo **`docker-compose`** para levantar los contenedores en cada servidor.

---

### Puntos Pendientes de Validación

* **Validación de Recursos:** Queda **pendiente validar con Solari** si es posible habilitar la cantidad total de servidores solicitados.

---

### Acuerdos y Tareas de Definición

Los siguientes puntos fueron acordados para su posterior revisión y definición:

1.  **Escalabilidad del Scrapper:** Revisar si el *scrapper* debe **escalar horizontalmente** o si debe permanecer en un único servidor.
2.  **Esquema de Despliegue:** Revisar y definir el esquema de despliegue para *frontend, backend, base de datos, rpa y scrapper*. El esquema debe poder soportar **despliegues automáticos** o con un **mínimo esfuerzo manual**, eliminando la dependencia del profesor Solari para la ejecución de nuevas versiones.
3.  **Actualización de Arquitectura (Interacciones):**
    * Agregar a la documentación de arquitectura la interacción pendiente entre el **Scrapper y la API de Core**.
    * Documentar el **retorno (lectura exitosa o no)** del mensaje en la cola de RabbitMQ desde **RPA y Scrapper**.
4.  **Actualización de Arquitectura (Simbología):**
    * Agregar un **icono de *cronjob*** para el *scrapper* en el diagrama de arquitectura.
    * Agregar un **icono de *contenedor*** a todos los componentes que se desplieguen como tal (*backend, frontend, reverse proxy, rpa, scrapper*).

---

### Próximas Tareas Prioritarias

* **Documentación de Infraestructura:** Terminar la **guía de instalación de servidores**.
* **Automatización de Despliegues:** Elaborar el **proceso/guía de despliegue de aplicaciones**.
* **Integración de Mensajería:** Modificar los módulos **RPA y Scrapper** para que realicen la lectura de datos desde la **cola de RabbitMQ**.
