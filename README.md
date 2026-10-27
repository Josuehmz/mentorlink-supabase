# MentorLink · Infraestructura con Supabase e IA

Base de datos (perfiles, sesiones y mensajes con RLS) y configuración de autenticación
(Email/Password y Google OAuth) de una plataforma de mentorías en Supabase, generadas con un
asistente de IA, aplicadas con la CLI de Supabase en un Supabase local y verificadas con 41
pruebas pgTAP (`supabase test db`) y 25 comprobaciones de RLS.

- **Documento único de la entrega:** [`ENTREGA.md`](ENTREGA.md) (también en PDF: [`ENTREGA.pdf`](ENTREGA.pdf)).
- **Materia:** SWNT.
- **Integrante:** Josué David Hernández Martínez.
- **Fecha de entrega:** 29 de octubre de 2026.
- **Qué es real:** la CLI de Supabase 2.122.0 se ejecutó (`init`, `migration new`, `start`,
  `db reset`, `migration list --local`, `test db`, `stop`) con la salida guardada en
  [`docs/evidencia/cli/`](docs/evidencia/cli/); `supabase test db` pasó 41 de 41
  ([log](docs/evidencia/cli/08-test-db.txt)). **Qué no se ejecutó:** `supabase login`, `link` y
  `db push`, y la configuración del Dashboard, porque no hay proyecto en la nube.
  Detalle en [Qué es real y qué no se ejecutó](#qué-es-real-y-qué-no-se-ejecutó).
- **Quién es mentor:** todo registro nace `estudiante` (el `rol` que mande el cliente se ignora);
  a mentor solo promueve `service_role`. Ver [Verificación](docs/01-esquema-y-rls.md#16-verificación).

## Entregable de la rúbrica → archivo

| Entregable del enunciado | Archivo principal | Archivos de apoyo |
|---|---|---|
| Scripts SQL generados (tablas y políticas RLS completas) | [`docs/01-esquema-y-rls.md`](docs/01-esquema-y-rls.md) | Fuente de verdad: [`supabase/migrations/20261027004403_inicializar_esquema.sql`](supabase/migrations/20261027004403_inicializar_esquema.sql) · pgTAP: [`supabase/tests/mentorlink_rls_test.sql`](supabase/tests/mentorlink_rls_test.sql) · prueba con avisos: [`supabase/pruebas/rls.sql`](supabase/pruebas/rls.sql) · datos: [`supabase/seed.sql`](supabase/seed.sql) |
| Prompt de IA utilizado (texto exacto) | [`docs/02-prompts-ia.md`](docs/02-prompts-ia.md) | [`docs/ia/prompt-maestro.txt`](docs/ia/prompt-maestro.txt) · [`docs/ia/respuesta-1.md`](docs/ia/respuesta-1.md) · [`docs/ia/prompt-refinamiento-1.txt`](docs/ia/prompt-refinamiento-1.txt) · [`docs/ia/respuesta-2.md`](docs/ia/respuesta-2.md) |
| Capturas o log de comandos de la CLI | [`docs/03-cli-supabase.md`](docs/03-cli-supabase.md) | Log real de la CLI: [`docs/evidencia/cli/`](docs/evidencia/cli/) (`04-start`, `05-db-reset`, `06-migration-list-local`, `08-test-db`, …) · config: [`supabase/config.toml`](supabase/config.toml) · prueba sin CLI: [`docs/evidencia/salida-pruebas-rls.txt`](docs/evidencia/salida-pruebas-rls.txt) |
| Guía de configuración Auth (3 pasos para Google) | [`docs/04-guia-auth-google.md`](docs/04-guia-auth-google.md) | [`.env.example`](.env.example) |
| Auditoría IA (cuatro ejes de la plataforma) | [`docs/05-auditoria-ia.md`](docs/05-auditoria-ia.md) | |

## Criterio de la rúbrica → dónde se demuestra

| Criterio (nivel Excelente) | Dónde se demuestra |
|---|---|
| Arquitectura de datos: relaciones correctas | [Modelo de datos](docs/01-esquema-y-rls.md#11-modelo-de-datos): `perfiles.id` → `auth.users(id)`, `sesiones` → `perfiles` (mentor y estudiante), `mensajes` → `sesiones` y `perfiles`, todas con `on delete cascade` justificado |
| Tipos óptimos y restricciones | [Tipos y restricciones](docs/01-esquema-y-rls.md#12-tipos-y-restricciones): `enum` para rol y estado, `timestamptz`, `bigint identity`, `check` de longitud y no vacío, `mentor_id <> estudiante_id`, índices en las FK |
| RLS funcionales que garantizan la privacidad | [Políticas RLS](docs/01-esquema-y-rls.md#14-políticas-rls) y [Verificación](docs/01-esquema-y-rls.md#16-verificación): RLS en las tres tablas, privilegios por columna, 7 políticas con `(select auth.uid())`, rol inicial fijo en `estudiante` (sonda del rol), 41 de 41 en [`supabase test db`](docs/evidencia/cli/08-test-db.txt) ([detalle](docs/evidencia/cli/09-test-db-detalle-tap.txt)) |
| Ingeniería de prompts: claros, técnicos y estructurados | [Prompt maestro](docs/02-prompts-ia.md#21-prompt-maestro-texto-exacto): bloques ROL, CONTEXTO, TAREA, RESTRICCIONES TÉCNICAS, SEGURIDAD y FORMATO DE SALIDA |
| Control total del resultado | [Refinamiento](docs/02-prompts-ia.md#22-prompt-de-refinamiento-texto-exacto), [qué cambió](docs/02-prompts-ia.md#23-qué-cambió-entre-la-respuesta-1-y-la-2) y [corrección tras la auditoría](docs/02-prompts-ia.md#25-corrección-tras-la-auditoría-el-rol-ya-no-sale-de-los-metadatos): la respuesta 1 falló una comprobación y se corrigió con un prompt acotado; una auditoría cruzada encontró que el rol venía de los metadatos del cliente y se fijó en `estudiante` |
| Dominio de la CLI de Supabase | [Log real](docs/03-cli-supabase.md#32-log-real-supabase-local): `init`, `migration new inicializar_esquema`, `start -x …`, `db reset`, `migration list --local`, `test db`, `stop --no-backup`, ejecutados con salida en [`docs/evidencia/cli/`](docs/evidencia/cli/); [nube, no ejecutado](docs/03-cli-supabase.md#33-pasos-del-proyecto-en-la-nube-no-ejecutados): `login`, `link`, `db push --dry-run`, `db push` |
| Configuración de proveedores OAuth | [Google OAuth en 3 pasos](docs/04-guia-auth-google.md#42-google-oauth-en-3-pasos) y [Email/Password](docs/04-guia-auth-google.md#41-emailpassword) |

## Árbol del repositorio

```text
mentorlink-supabase/
├── README.md                     ← este mapa
├── ENTREGA.md                    ← documento único de la entrega (generado desde docs/)
├── ENTREGA.pdf                   ← el mismo documento en PDF
├── .env.example                  ← variables de Google OAuth para local (solo marcadores)
├── docs/
│   ├── 01-esquema-y-rls.md       ← entregable 1: modelo, decisiones, políticas, pruebas y SQL completo
│   ├── 02-prompts-ia.md          ← entregable 2: prompts exactos y qué cambió entre respuestas
│   ├── 03-cli-supabase.md        ← entregable 3: log real de la CLI (local) y pasos de la nube (no ejecutados)
│   ├── 04-guia-auth-google.md    ← entregable 4: Email/Password y Google OAuth en 3 pasos
│   ├── 05-auditoria-ia.md        ← los cuatro ejes de la auditoría IA
│   ├── ia/                       ← prompts y respuestas literales de la IA
│   │   ├── prompt-maestro.txt
│   │   ├── respuesta-1.md
│   │   ├── respuesta-1-migracion.sql   ← bloque SQL de la respuesta 1, extraído sin cambios
│   │   ├── prompt-refinamiento-1.txt
│   │   ├── respuesta-2.md
│   │   └── respuesta-2-migracion.sql   ← bloque SQL de la respuesta 2 (la migración antes de la corrección del rol)
│   └── evidencia/
│       ├── cli/                                 ← salida real de cada comando de la CLI (01-version … 13-stop)
│       ├── prueba-1-respuesta-sin-refinar.txt   ← la respuesta 1 falla la prueba 15
│       └── salida-pruebas-rls.txt               ← la migración final en el stub: 25 de 25
├── supabase/                     ← proyecto de la CLI (creado con supabase init)
│   ├── config.toml               ← generado por supabase init, sin editar
│   ├── migrations/
│   │   └── 20261027004403_inicializar_esquema.sql   ← FUENTE DE VERDAD del SQL (nombre de supabase migration new)
│   ├── seed.sql                  ← 2 perfiles de ejemplo; la mentora se promueve con un update
│   ├── tests/
│   │   └── mentorlink_rls_test.sql   ← 41 pruebas pgTAP (supabase test db)
│   └── pruebas/
│       └── rls.sql               ← prueba de RLS con avisos y 4 usuarios simulados (termina en rollback)
├── pruebas-locales/              ← prueba rápida sin la CLI de Supabase
│   ├── stub-supabase.sql         ← roles, auth.users y auth.uid() como en Supabase
│   └── ejecutar-pruebas.sh       ← PostgreSQL 17 en Docker: stub → migración → seed → rls.sql
└── herramientas/
    └── armar_entrega.py          ← sincroniza el SQL y los prompts en docs/, arma ENTREGA.md y verifica enlaces
```

## Cómo reproducir

Con la CLI de Supabase y Docker (ejecutado así; salida en [`docs/evidencia/cli/`](docs/evidencia/cli/)):

```bash
supabase start -x studio,realtime,storage-api,imgproxy,edge-runtime,logflare,vector,supavisor,mailpit,postgres-meta
supabase db reset                 # aplica supabase/migrations/ y supabase/seed.sql
supabase migration list --local   # una migración: 20261027004403
supabase test db                  # 41 pruebas pgTAP: "Result: PASS"
supabase stop --no-backup
```

Sin la CLI (solo Docker) y para comprobar que la documentación no diverge del SQL:

```bash
bash pruebas-locales/ejecutar-pruebas.sh           # termina con "TODAS LAS PRUEBAS DE RLS PASARON"
python herramientas/armar_entrega.py --verificar   # docs/ y ENTREGA.md coinciden con el SQL y los prompts
```

En la nube (no ejecutado: no hay proyecto; detalle en
[`docs/03-cli-supabase.md`](docs/03-cli-supabase.md#33-pasos-del-proyecto-en-la-nube-no-ejecutados)):

```bash
supabase login
supabase link --project-ref <project-ref>
supabase db push --dry-run && supabase db push
supabase migration list
```

## Qué es real y qué no se ejecutó

| Parte | Estado |
|---|---|
| SQL de la migración (tablas, triggers, privilegios, RLS) | Real: generado por IA, corregido tras auditoría (rol fijo en `estudiante`) y aplicado con `supabase db reset` |
| Pruebas pgTAP (`supabase/tests/mentorlink_rls_test.sql`) | Real: 41 de 41 con `supabase test db` ([log](docs/evidencia/cli/08-test-db.txt)) |
| Pruebas de RLS con avisos (`supabase/pruebas/rls.sql`) | Real: 25 de 25 en Supabase local ([log](docs/evidencia/cli/12-rls-sql-en-supabase-local.txt)) y en el stub ([log](docs/evidencia/salida-pruebas-rls.txt)) |
| Prompts y respuestas de la IA | Reales y literales |
| CLI en local (`init`, `migration new`, `start`, `db reset`, `migration list --local`, `test db`, `status`, `stop`) | **Ejecutada**, salida real en [`docs/evidencia/cli/`](docs/evidencia/cli/) (claves como `<redactado>`) |
| CLI en la nube (`login`, `link`, `db push`, `migration list` remoto) | **No ejecutada**: no existe proyecto en la nube |
| Configuración del Dashboard (Email/Password, Google) | **Guía**, no ejecutada: no existe proyecto de Supabase ni cliente OAuth de Google |
| Credenciales | Ninguna real: `<project-ref>`, Client ID y Client Secret son marcadores |
