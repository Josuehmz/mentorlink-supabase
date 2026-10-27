# 3. Supabase CLI: comandos y evidencia

Esta sección documenta cómo se crea y se aplica la migración con la CLI de Supabase. **En el equipo
donde se hizo el trabajo no está instalada la CLI de Supabase**, así que los comandos de la CLI se
presentan como **simulados**: la secuencia es la correcta según la documentación oficial y la
salida que se muestra es la **esperada**, no capturada. Lo que sí se ejecutó de verdad es el SQL:
la migración y las pruebas de RLS corrieron en PostgreSQL 17 dentro de Docker (sección 3.3).

## 3.1 Qué es real y qué es simulado

| Elemento | Estado | Evidencia |
|---|---|---|
| Estructura `supabase/migrations/<timestamp>_inicializar_esquema.sql` | Real (archivo creado a mano con el formato de nombre de la CLI: `date -u +%Y%m%d%H%M%S`) | [`supabase/migrations/`](../supabase/migrations/) |
| `supabase init`, `login`, `link`, `migration new`, `db push`, `migration list`, `db reset` | **Simulado** | Sección 3.2 |
| Migración aplicada a un PostgreSQL 17 | **Real** | [`evidencia/salida-pruebas-rls.txt`](evidencia/salida-pruebas-rls.txt) |
| Pruebas de RLS con cuatro usuarios | **Real** (25 de 25) | Misma salida |
| Proyecto remoto de Supabase | No existe | El `<project-ref>` es un marcador |

## 3.2 Secuencia de comandos (simulados)

Requisitos: Supabase CLI instalada (por ejemplo `npx supabase <comando>` o el binario de la
página de instalación) y, para el entorno local, Docker en marcha.

### Paso 1. Inicializar el proyecto

```bash
supabase init
```

Crea la carpeta `supabase/` con `config.toml`. Salida esperada (no capturada): `Finished supabase init.`

### Paso 2. Iniciar sesión en la cuenta de Supabase

```bash
supabase login
```

Abre el navegador para autorizar la CLI y guarda un token de acceso local. Salida esperada:
`You are now logged in. Happy coding!`. En CI se usa la variable `SUPABASE_ACCESS_TOKEN` en vez de
este comando.

### Paso 3. Vincular el proyecto remoto

```bash
supabase link --project-ref <project-ref>
```

`<project-ref>` es el identificador del proyecto (el subdominio de `https://<project-ref>.supabase.co`,
también en Project Settings). Pide la contraseña de la base de datos. Salida esperada:
`Finished supabase link.`

### Paso 4. Crear la migración

```bash
supabase migration new inicializar_esquema
```

Crea un archivo vacío con la marca de tiempo UTC. Salida esperada:
`Created new migration at supabase/migrations/<timestamp>_inicializar_esquema.sql`.
En este repositorio ese archivo es
[`20261027000855_inicializar_esquema.sql`](../supabase/migrations/20261027000855_inicializar_esquema.sql)
y su contenido es el SQL generado por la IA ([sección 2](02-prompts-ia.md)).

### Paso 5. Probar en local antes de tocar el remoto (opcional, recomendado)

```bash
supabase start          # levanta Postgres, Auth y la API en Docker
supabase db reset       # recrea la base local: aplica migrations/ y luego seed.sql
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -v ON_ERROR_STOP=1 -f supabase/pruebas/rls.sql
```

Salida esperada de `db reset`: líneas `Applying migration 20261027000855_inicializar_esquema.sql...`
y `Seeding data from supabase/seed.sql...`, y al final `Finished supabase db reset`. La prueba
debería imprimir lo mismo que la corrida real de la sección 3.3.

### Paso 6. Aplicar la migración al proyecto remoto

```bash
supabase db push --dry-run   # muestra qué migraciones aplicaría, sin aplicarlas
supabase db push             # aplica las migraciones pendientes al proyecto vinculado
```

Salida esperada de `db push`: pregunta `Do you want to push these migrations to the remote
database?` con la lista `• 20261027000855_inicializar_esquema.sql`, y tras confirmar,
`Applying migration 20261027000855_inicializar_esquema.sql...` y `Finished supabase db push.`
`seed.sql` no se envía al remoto salvo con `--include-seed`.

### Paso 7. Comprobar el historial

```bash
supabase migration list
```

Salida esperada: una tabla con columnas `Local`, `Remote` y `Time (UTC)` donde
`20261027000855` aparece en ambas columnas (aplicada en local y en remoto).

## 3.3 Evidencia real: la migración corriendo en PostgreSQL 17 (Docker)

Sin la CLI, el SQL se probó con [`pruebas-locales/ejecutar-pruebas.sh`](../pruebas-locales/ejecutar-pruebas.sh),
que levanta un contenedor desechable `postgres:17-alpine`, carga un stub con lo que Supabase ya trae
antes de cualquier migración ([`pruebas-locales/stub-supabase.sql`](../pruebas-locales/stub-supabase.sql):
roles `anon`, `authenticated` y `service_role`, la tabla `auth.users`, la función `auth.uid()` con
la misma definición que en Supabase y los privilegios por defecto), aplica la migración, aplica el
seed dentro de una transacción revertida y corre [`supabase/pruebas/rls.sql`](../supabase/pruebas/rls.sql).

```bash
bash pruebas-locales/ejecutar-pruebas.sh
```

Inicio de la salida capturada (completa en [`evidencia/salida-pruebas-rls.txt`](evidencia/salida-pruebas-rls.txt)):

```text
== Servidor: PostgreSQL 17.9 on x86_64-pc-linux-musl, compiled by gcc (Alpine 15.2.0) 15.2.0, 64-bit
== 1. Stub de Supabase (roles, auth.users, auth.uid(), privilegios por defecto)
== 2. Migración: supabase/migrations/20261027000855_inicializar_esquema.sql
   tablas: mensajes (rls=true), perfiles (rls=true), sesiones (rls=true)
   políticas: 7
== 3. Seed (dentro de una transacción revertida)
perfiles creados por el seed: 2
== 4. Pruebas de RLS: supabase/pruebas/rls.sql
NOTICE:  OK 01 handle_new_user crea los 4 perfiles con rol y nombre correctos (rol "admin" -> estudiante)
...
NOTICE:  OK 25 la regla de roles también aplica a service_role (trigger)
NOTICE:  TODAS LAS PRUEBAS DE RLS PASARON
```

Límite de esta prueba: el stub no es Supabase completo (no hay GoTrue ni PostgREST). Prueba el SQL,
los privilegios y las políticas con los mismos roles y la misma `auth.uid()`; no prueba el flujo
HTTP de la API ni el inicio de sesión real.

## Fuentes

- Primeros pasos con la CLI: https://supabase.com/docs/guides/local-development/cli/getting-started
- Referencia de la CLI (`init`, `login`, `link`, `migration new`, `db push`, `migration list`, `db reset`): https://supabase.com/docs/reference/cli/introduction
- Migraciones de base de datos: https://supabase.com/docs/guides/deployment/database-migrations
