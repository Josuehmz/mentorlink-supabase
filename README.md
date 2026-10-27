# MentorLink · Infraestructura con Supabase e IA

Base de datos (perfiles, sesiones y mensajes con RLS) y configuración de autenticación
(Email/Password y Google OAuth) de una plataforma de mentorías en Supabase, generadas con un
asistente de IA, ejecutadas en PostgreSQL 17 y verificadas con 25 pruebas de RLS.

- **Documento único de la entrega:** [`ENTREGA.md`](ENTREGA.md) (también en PDF: [`ENTREGA.pdf`](ENTREGA.pdf)).
- **Fecha de entrega:** 29 de octubre de 2026.
- **Qué es simulado:** los comandos de la CLI de Supabase (no está instalada) y la configuración del
  Dashboard (no hay proyecto remoto). **Qué es real:** el SQL corrió en PostgreSQL 17 y las 25
  comprobaciones de RLS pasaron ([salida capturada](docs/evidencia/salida-pruebas-rls.txt)).
  Detalle en [Qué es real y qué es simulado](#qué-es-real-y-qué-es-simulado).

## Entregable de la rúbrica → archivo

| Entregable del enunciado | Archivo principal | Archivos de apoyo |
|---|---|---|
| Scripts SQL generados (tablas y políticas RLS completas) | [`docs/01-esquema-y-rls.md`](docs/01-esquema-y-rls.md) | Fuente de verdad: [`supabase/migrations/20261027000855_inicializar_esquema.sql`](supabase/migrations/20261027000855_inicializar_esquema.sql) · prueba: [`supabase/pruebas/rls.sql`](supabase/pruebas/rls.sql) · datos: [`supabase/seed.sql`](supabase/seed.sql) |
| Prompt de IA utilizado (texto exacto) | [`docs/02-prompts-ia.md`](docs/02-prompts-ia.md) | [`docs/ia/prompt-maestro.txt`](docs/ia/prompt-maestro.txt) · [`docs/ia/respuesta-1.md`](docs/ia/respuesta-1.md) · [`docs/ia/prompt-refinamiento-1.txt`](docs/ia/prompt-refinamiento-1.txt) · [`docs/ia/respuesta-2.md`](docs/ia/respuesta-2.md) |
| Capturas o log de comandos de la CLI | [`docs/03-cli-supabase.md`](docs/03-cli-supabase.md) | Log real: [`docs/evidencia/salida-pruebas-rls.txt`](docs/evidencia/salida-pruebas-rls.txt) · [`docs/evidencia/prueba-1-respuesta-sin-refinar.txt`](docs/evidencia/prueba-1-respuesta-sin-refinar.txt) |
| Guía de configuración Auth (3 pasos para Google) | [`docs/04-guia-auth-google.md`](docs/04-guia-auth-google.md) | [`.env.example`](.env.example) |
| Auditoría IA (cuatro ejes de la plataforma) | [`docs/05-auditoria-ia.md`](docs/05-auditoria-ia.md) | |

## Criterio de la rúbrica → dónde se demuestra

| Criterio (nivel Excelente) | Dónde se demuestra |
|---|---|
| Arquitectura de datos: relaciones correctas | [Modelo de datos](docs/01-esquema-y-rls.md#11-modelo-de-datos): `perfiles.id` → `auth.users(id)`, `sesiones` → `perfiles` (mentor y estudiante), `mensajes` → `sesiones` y `perfiles`, todas con `on delete cascade` justificado |
| Tipos óptimos y restricciones | [Tipos y restricciones](docs/01-esquema-y-rls.md#12-tipos-y-restricciones): `enum` para rol y estado, `timestamptz`, `bigint identity`, `check` de longitud y no vacío, `mentor_id <> estudiante_id`, índices en las FK |
| RLS funcionales que garantizan la privacidad | [Políticas RLS](docs/01-esquema-y-rls.md#14-políticas-rls) y [Verificación](docs/01-esquema-y-rls.md#16-verificación): RLS en las tres tablas, privilegios por columna, 7 políticas con `(select auth.uid())`, 25 de 25 pruebas en verde |
| Ingeniería de prompts: claros, técnicos y estructurados | [Prompt maestro](docs/02-prompts-ia.md#21-prompt-maestro-texto-exacto): bloques ROL, CONTEXTO, TAREA, RESTRICCIONES TÉCNICAS, SEGURIDAD y FORMATO DE SALIDA |
| Control total del resultado | [Refinamiento](docs/02-prompts-ia.md#22-prompt-de-refinamiento-texto-exacto) y [qué cambió](docs/02-prompts-ia.md#23-qué-cambió-entre-la-respuesta-1-y-la-2): la respuesta 1 se probó, falló una comprobación, se corrigió con un prompt acotado y la respuesta 2 pasó todo |
| Dominio de la CLI de Supabase | [Secuencia de comandos](docs/03-cli-supabase.md#32-secuencia-de-comandos-simulados): `init`, `login`, `link`, `migration new inicializar_esquema`, `db reset`, `db push --dry-run`, `db push`, `migration list` |
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
│   ├── 03-cli-supabase.md        ← entregable 3: comandos de la CLI (simulados) y log real de Docker
│   ├── 04-guia-auth-google.md    ← entregable 4: Email/Password y Google OAuth en 3 pasos
│   ├── 05-auditoria-ia.md        ← los cuatro ejes de la auditoría IA
│   ├── ia/                       ← prompts y respuestas literales de la IA
│   │   ├── prompt-maestro.txt
│   │   ├── respuesta-1.md
│   │   ├── respuesta-1-migracion.sql   ← bloque SQL de la respuesta 1, extraído sin cambios
│   │   ├── prompt-refinamiento-1.txt
│   │   ├── respuesta-2.md
│   │   └── respuesta-2-migracion.sql   ← bloque SQL de la respuesta 2 (= la migración)
│   └── evidencia/
│       ├── prueba-1-respuesta-sin-refinar.txt   ← la respuesta 1 falla la prueba 15
│       └── salida-pruebas-rls.txt               ← la migración final: 25 de 25
├── supabase/                     ← estructura de un proyecto de Supabase CLI
│   ├── migrations/
│   │   └── 20261027000855_inicializar_esquema.sql   ← FUENTE DE VERDAD del SQL
│   ├── seed.sql                  ← 2 perfiles de ejemplo (para supabase db reset)
│   └── pruebas/
│       └── rls.sql               ← prueba de RLS con 4 usuarios simulados (termina en rollback)
├── pruebas-locales/              ← cómo se probó sin la CLI de Supabase
│   ├── stub-supabase.sql         ← roles, auth.users y auth.uid() como en Supabase
│   └── ejecutar-pruebas.sh       ← PostgreSQL 17 en Docker: stub → migración → seed → rls.sql
└── herramientas/
    └── armar_entrega.py          ← sincroniza el SQL y los prompts en docs/, arma ENTREGA.md y verifica enlaces
```

## Cómo reproducir

Pruebas reales, sin la CLI de Supabase (requiere Docker):

```bash
bash pruebas-locales/ejecutar-pruebas.sh           # termina con "TODAS LAS PRUEBAS DE RLS PASARON"
python herramientas/armar_entrega.py --verificar   # docs/ y ENTREGA.md coinciden con el SQL y los prompts
```

Con la CLI de Supabase (no ejecutado en este trabajo; detalle y salidas esperadas en
[`docs/03-cli-supabase.md`](docs/03-cli-supabase.md)):

```bash
supabase init
supabase login
supabase link --project-ref <project-ref>
supabase migration new inicializar_esquema   # aquí va el SQL de docs/01
supabase start && supabase db reset          # local: migraciones + seed
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/pruebas/rls.sql
supabase db push --dry-run && supabase db push
supabase migration list
```

## Qué es real y qué es simulado

| Parte | Estado |
|---|---|
| SQL de la migración (tablas, triggers, privilegios, RLS) | Real: generado por IA, ejecutado en PostgreSQL 17.9 (Docker) |
| Pruebas de RLS (`supabase/pruebas/rls.sql`) | Real: 25 de 25 en verde, salida capturada |
| Prompts y respuestas de la IA | Reales y literales |
| Supabase local | Sustituido por un stub (`pruebas-locales/stub-supabase.sql`): mismos roles y misma `auth.uid()`, sin GoTrue ni PostgREST |
| Comandos de la CLI de Supabase y su salida | **Simulados**: secuencia según la documentación oficial; salida esperada, no capturada |
| Configuración del Dashboard (Email/Password, Google) | **Guía**, no ejecutada: no existe proyecto de Supabase ni cliente OAuth de Google |
| Credenciales | Ninguna real: `<project-ref>`, Client ID y Client Secret son marcadores |
