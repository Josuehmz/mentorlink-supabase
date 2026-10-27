# 3. Supabase CLI: comandos y evidencia

Esta sección documenta cómo se crea, se aplica y se prueba la migración con la CLI de Supabase.
**La CLI se ejecutó de verdad** (Supabase CLI 2.122.0, Windows 11 con Docker Desktop, 26 de
octubre de 2026) contra un Supabase local levantado con `supabase start`. Cada comando dejó su
salida, con fecha, versión y código de salida, en [`evidencia/cli/`](evidencia/cli/). Los pasos
que necesitan un proyecto en la nube (`login`, `link`, `db push`) **no se ejecutaron**, porque
ese proyecto no existe; quedan documentados en la sección 3.3.

## 3.1 Qué es real y qué no se ejecutó

| Elemento | Estado | Evidencia |
|---|---|---|
| `supabase --version`, `init`, `migration new inicializar_esquema` | **Ejecutado** | [`01`](evidencia/cli/01-version.txt), [`02`](evidencia/cli/02-init.txt), [`03`](evidencia/cli/03-migration-new.txt) |
| `supabase start` (solo db, auth, rest y kong) | **Ejecutado**: aplicó la migración y el seed | [`04-start.txt`](evidencia/cli/04-start.txt) |
| `supabase db reset` | **Ejecutado** | [`05-db-reset.txt`](evidencia/cli/05-db-reset.txt) |
| `supabase migration list --local` | **Ejecutado**: una sola migración, aplicada | [`06-migration-list-local.txt`](evidencia/cli/06-migration-list-local.txt) |
| `supabase test db` (pgTAP) | **Ejecutado**: 41 de 41 | [`08-test-db.txt`](evidencia/cli/08-test-db.txt) y detalle [`09`](evidencia/cli/09-test-db-detalle-tap.txt) |
| `supabase status`, `supabase stop --no-backup` | **Ejecutado** (claves como `<redactado>`) | [`10-status.txt`](evidencia/cli/10-status.txt), [`13-stop.txt`](evidencia/cli/13-stop.txt) |
| Prueba con avisos `supabase/pruebas/rls.sql` en el Supabase local | **Ejecutado**: 25 de 25 | [`12-rls-sql-en-supabase-local.txt`](evidencia/cli/12-rls-sql-en-supabase-local.txt) |
| `supabase login`, `link`, `db push --dry-run`, `db push`, `migration list` remoto | **No ejecutado**: no hay proyecto en la nube | Sección 3.3 |

## 3.2 Log real: Supabase local

Todos los comandos se corrieron desde la raíz del repositorio. Se añadió `--agent no` porque la
CLI 2.122.0 detecta que la terminal no es interactiva y, sin esa opción, responde en JSON en vez
de texto (pasó con el primer `migration new`; ese archivo vacío se borró y el comando se repitió).
Las salidas largas están completas en cada archivo; aquí van los fragmentos que importan.

### Paso 1. Versión e inicialización

```text
$ supabase --version
2.122.0

$ supabase init
Finished supabase init.
```

`init` creó [`supabase/config.toml`](../supabase/config.toml) (`project_id = "mentorlink-supabase"`,
Postgres 17, seed `./seed.sql`) y `supabase/.gitignore`. No se editó.

### Paso 2. Crear la migración

```text
$ supabase migration new inicializar_esquema --agent no
Created new migration at supabase\migrations\20261027004403_inicializar_esquema.sql
```

El archivo vacío que creó la CLI recibió el SQL ([sección 1.8](01-esquema-y-rls.md#18-script-sql-completo))
y la versión anterior, que tenía un nombre puesto a mano, se eliminó: en
[`supabase/migrations/`](../supabase/migrations/) queda una sola migración,
[`20261027004403_inicializar_esquema.sql`](../supabase/migrations/20261027004403_inicializar_esquema.sql).

### Paso 3. Levantar Supabase local con lo mínimo

```bash
supabase start -x studio,realtime,storage-api,imgproxy,edge-runtime,logflare,vector,supavisor,mailpit,postgres-meta
```

Los nombres de `-x` son los que lista `supabase start --help`. Quedan en marcha Postgres, GoTrue
(Auth), PostgREST y Kong, que es lo que necesita la migración. Fragmento de
[`04-start.txt`](evidencia/cli/04-start.txt):

```text
Starting database...
Initialising schema...
Seeding globals from roles.sql...
Applying migration 20261027004403_inicializar_esquema.sql...
Seeding data from supabase/seed.sql...
Starting containers...
Waiting for health checks...
Started supabase local development setup.
```

Aun con `-x`, la CLI descargó las imágenes de `realtime` y `storage-api` para inicializar sus
esquemas; no dejó esos contenedores corriendo (ver [`10-status.txt`](evidencia/cli/10-status.txt)).

### Paso 4. Recrear la base: migración y seed

```text
$ supabase db reset --agent no
Resetting local database...
Recreating database...
Initialising schema...
Seeding globals from roles.sql...
Applying migration 20261027004403_inicializar_esquema.sql...
Seeding data from supabase/seed.sql...
Restarting containers...
Finished supabase db reset on branch main.
```

El seed deja a «Mentora Demo» como `mentor` (promovida con un `update`, como haría un
administrador) y a «Estudiante Demo» como `estudiante`; la consulta está al inicio de
[`11-rls-sql-en-supabase-local-intento-1-falla.txt`](evidencia/cli/11-rls-sql-en-supabase-local-intento-1-falla.txt).

### Paso 5. Historial de migraciones

```text
$ supabase migration list --local --agent no
Connecting to local database...

   Local            | Remote           | Time (UTC)
  ------------------|------------------|-----------------------
   `20261027004403` | `20261027004403` | `2026-10-27 00:44:03`
```

Con `--local`, la columna `Remote` es la base local: la migración está en el disco y aplicada.

### Paso 6. Pruebas pgTAP

```text
$ supabase test db --agent no
Connecting to local database...
.../supabase/tests/mentorlink_rls_test.sql .. ok
All tests successful.
Files=1, Tests=41,  1 wallclock secs ( 0.14 usr  0.09 sys +  0.05 cusr  0.06 csys =  0.34 CPU)
Result: PASS
```

[`supabase/tests/mentorlink_rls_test.sql`](../supabase/tests/mentorlink_rls_test.sql) tiene 41
pruebas. `pg_prove` solo imprime el resumen; la lista `ok 1` … `ok 41` con el nombre de cada
prueba está en [`09-test-db-detalle-tap.txt`](evidencia/cli/09-test-db-detalle-tap.txt) (el mismo
archivo pasado por `psql` en el contenedor de la base).

El primer intento falló antes de la primera prueba
([`07-test-db-intento-1-falla.txt`](evidencia/cli/07-test-db-intento-1-falla.txt)): la prueba hacía
`set role supabase_auth_admin` para registrar un usuario como lo hace GoTrue, y en Supabase local el
rol `postgres` no tiene ese permiso. El usuario se inserta ahora como `postgres`; el trigger
`handle_new_user` es el mismo.

La prueba con avisos [`supabase/pruebas/rls.sql`](../supabase/pruebas/rls.sql) también corrió contra
esta base: 25 de 25 ([`12-rls-sql-en-supabase-local.txt`](evidencia/cli/12-rls-sql-en-supabase-local.txt)).
Su primer intento falló porque contaba todos los perfiles y el seed ya tenía una mentora
([`11`](evidencia/cli/11-rls-sql-en-supabase-local-intento-1-falla.txt)); los conteos se limitaron a
los cuatro usuarios de la prueba.

### Paso 7. Estado y apagado

`supabase status` ([`10-status.txt`](evidencia/cli/10-status.txt)) muestra `Not linked.` (no hay
proyecto en la nube), los servicios excluidos y las URL locales; las claves aparecen como
`<redactado>`. Al final:

```text
$ supabase stop --no-backup --agent no
Stopping containers...
Stopped supabase local development setup.
```

## 3.3 Pasos del proyecto en la nube (no ejecutados)

No existe un proyecto de Supabase en la nube para MentorLink, así que estos pasos **no se
ejecutaron** y no hay salida que mostrar. Esta es la secuencia, según la documentación oficial:

```bash
supabase login                              # abre el navegador y guarda un token local
supabase link --project-ref <project-ref>   # pide la contraseña de la base del proyecto
supabase db push --dry-run                  # muestra qué migraciones aplicaría, sin aplicarlas
supabase db push                            # aplica 20261027004403_inicializar_esquema.sql
supabase migration list                     # Local y Remote deberían mostrar 20261027004403
```

- `<project-ref>` es el subdominio de `https://<project-ref>.supabase.co` (también en Project
  Settings). En CI se usa la variable `SUPABASE_ACCESS_TOKEN` en vez de `supabase login`.
- `db push` no envía `seed.sql` salvo con `--include-seed`. En la nube, los mentores se promueven
  con `update public.perfiles set rol = 'mentor' ...` desde el SQL Editor o el backend.
- `supabase test db --linked` correría las mismas 41 pruebas contra el proyecto vinculado.

## 3.4 Prueba previa sin la CLI (PostgreSQL 17 con un stub)

Antes de usar la CLI, el SQL se probó con
[`pruebas-locales/ejecutar-pruebas.sh`](../pruebas-locales/ejecutar-pruebas.sh): un contenedor
desechable `postgres:17-alpine` con un stub de lo que Supabase trae antes de cualquier migración
([`pruebas-locales/stub-supabase.sql`](../pruebas-locales/stub-supabase.sql): roles `anon`,
`authenticated` y `service_role`, la tabla `auth.users`, `auth.uid()` y los privilegios por
defecto). Sigue sirviendo como prueba rápida sin la CLI:

```bash
bash pruebas-locales/ejecutar-pruebas.sh
```

Inicio de la salida (completa en [`evidencia/salida-pruebas-rls.txt`](evidencia/salida-pruebas-rls.txt)):

```text
== Servidor: PostgreSQL 17.9 on x86_64-pc-linux-musl, compiled by gcc (Alpine 15.2.0) 15.2.0, 64-bit
== 1. Stub de Supabase (roles, auth.users, auth.uid(), privilegios por defecto)
== 2. Migración: supabase/migrations/20261027004403_inicializar_esquema.sql
   tablas: mensajes (rls=true), perfiles (rls=true), sesiones (rls=true)
   políticas: 7
== 3. Seed (dentro de una transacción revertida)
perfiles creados por el seed: 2
== 4. Pruebas de RLS: supabase/pruebas/rls.sql
NOTICE:  OK 01 handle_new_user crea los 4 perfiles como estudiante aunque pidan "mentor" o "admin" (sonda del rol)
NOTICE:  OK 01 service_role promueve a Ana y a Dario a mentor
...
NOTICE:  OK 25 la regla de roles también aplica a service_role (trigger)
NOTICE:  TODAS LAS PRUEBAS DE RLS PASARON
```

El stub no tiene GoTrue ni PostgREST; por eso la evidencia principal es la de la sección 3.2.

## Fuentes

- Primeros pasos con la CLI: https://supabase.com/docs/guides/local-development/cli/getting-started
- Referencia de la CLI (`init`, `start`, `migration new`, `db reset`, `migration list`, `test db`, `link`, `db push`): https://supabase.com/docs/reference/cli/introduction
- Pruebas de base de datos con pgTAP: https://supabase.com/docs/guides/local-development/testing/overview
- Migraciones de base de datos: https://supabase.com/docs/guides/deployment/database-migrations
