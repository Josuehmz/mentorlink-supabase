# 2. Prompts de IA utilizados

El SQL no se escribió a mano: se le pidió a un asistente de IA con un prompt maestro estructurado
(rol, contexto, tarea, restricciones técnicas, seguridad y formato de salida), se ejecutó lo que
devolvió, se probó y se corrigió con un segundo prompt. Abajo están los dos prompts con su texto
exacto y lo que cambió entre una respuesta y otra.

| Paso | Archivo | Qué es |
|---|---|---|
| 1 | [`prompt-maestro.txt`](ia/prompt-maestro.txt) | Prompt maestro, texto exacto enviado |
| 2 | [`respuesta-1.md`](ia/respuesta-1.md) | Respuesta literal de la IA (SQL, tabla de políticas, riesgos) |
| 3 | [`prueba-1-respuesta-sin-refinar.txt`](evidencia/prueba-1-respuesta-sin-refinar.txt) | Esa respuesta ejecutada en PostgreSQL 17: 14 comprobaciones bien, falla la 15 |
| 4 | [`prompt-refinamiento-1.txt`](ia/prompt-refinamiento-1.txt) | Prompt de refinamiento, texto exacto enviado |
| 5 | [`respuesta-2.md`](ia/respuesta-2.md) | Respuesta literal refinada |
| 6 | [`20261027004403_inicializar_esquema.sql`](../supabase/migrations/20261027004403_inicializar_esquema.sql) | El SQL de la respuesta 2 más la corrección del rol ([2.5](#25-corrección-tras-la-auditoría-el-rol-ya-no-sale-de-los-metadatos)); nombre real de `supabase migration new` |
| 7 | [`salida-pruebas-rls.txt`](evidencia/salida-pruebas-rls.txt) | Migración final ejecutada: 25 de 25 en verde |

**Cómo se usó la IA:** cada prompt se envió a una sesión nueva de un asistente de IA (Claude) sin
acceso al resto del proyecto; la respuesta se guardó tal cual. El refinamiento se envió como
segundo turno, con el prompt maestro y la respuesta 1 como historial de la conversación. La revisión consistió en
ejecutar el SQL y las pruebas, no en retocar el código a mano.

## 2.1 Prompt maestro (texto exacto)

Por qué está armado así:

| Bloque del prompt | Qué controla |
|---|---|
| `# ROL` | Nivel de exigencia: SQL de producción, explícito y seguro por defecto |
| `# CONTEXTO` | El dato que cambia el diseño: el navegador usa la clave pública, así que la autorización va en la base de datos |
| `# TAREA` | Un solo archivo de migración con el nombre que usa la CLI; tablas y columnas del enunciado, sin extras |
| `# RESTRICCIONES TÉCNICAS` | Tipos, FK, `check`, índices, triggers y `search_path`; decisiones que debe justificar en comentarios |
| `# SEGURIDAD (RLS)` | Privilegios explícitos, `(select auth.uid())`, una política por operación y la regla exacta de cada tabla |
| `# FORMATO DE SALIDA` | Bloque SQL ordenado por secciones, tabla de políticas y máximo 5 riesgos: una salida que se puede revisar y probar |

<!-- INCLUIR: ia/prompt-maestro.txt -->
````text
# ROL
Actúa como Arquitecto de Bases de Datos senior especializado en Supabase (PostgreSQL 15+,
Supabase Auth y Row Level Security). Escribes SQL de producción: explícito, comentado y seguro
por defecto.

# CONTEXTO
MentorLink es una plataforma que conecta mentores expertos en tecnología con estudiantes.
Los usuarios se registran con Supabase Auth (email/contraseña y Google OAuth). El cliente usa
la API de Supabase (PostgREST) desde el navegador con la clave pública, así que toda la
autorización tiene que vivir en la base de datos. Presupuesto limitado: nada de servicios extra.

# TAREA
Genera UN solo archivo de migración para Supabase CLI
(supabase/migrations/<timestamp>_inicializar_esquema.sql) que cree el esquema y su seguridad.

## Tablas (esquema public, nombres en español y snake_case)
1. perfiles (id, nombre, bio, rol)
2. sesiones (id, mentor_id, estudiante_id, fecha, estado)
3. mensajes (id, sesion_id, remitente_id, contenido)
Puedes añadir columnas de auditoría (creado_en, actualizado_en) y nada más.

# RESTRICCIONES TÉCNICAS
- perfiles.id es uuid, clave primaria y FK a auth.users(id) con on delete cascade.
- rol y estado son tipos enum: rol_usuario (mentor, estudiante) y
  estado_sesion (pendiente, confirmada, completada, cancelada; default pendiente).
- Textos con check: nombre no vacío (tras trim) y máximo 120 caracteres; bio opcional, máximo
  1000; contenido de mensajes no vacío y máximo 2000.
- Fechas siempre timestamptz. sesiones: check mentor_id <> estudiante_id.
- Elige el tipo de cada id (uuid o bigint identity) y el on delete de cada FK, y justifícalo
  en un comentario de una línea.
- Índices en todas las columnas FK que se usen en políticas o joins.
- Trigger handle_new_user siguiendo el patrón oficial de Supabase (security definer,
  set search_path = ''): crea el perfil al registrarse, toma nombre de raw_user_meta_data
  ('nombre', luego 'full_name' de Google, luego la parte local del email) y rol de
  raw_user_meta_data->>'rol' (solo 'mentor' o 'estudiante'; cualquier otro valor, estudiante).
- Trigger que valide en sesiones que mentor_id apunta a un perfil con rol mentor y estudiante_id
  a uno con rol estudiante (aplica también a service_role, que se salta RLS).
- Trigger que mantenga actualizado_en.
- Toda función: set search_path = '' y nombres calificados con esquema.

# SEGURIDAD (RLS)
- Activa RLS en las tres tablas.
- Privilegios explícitos: revoca todo a anon y authenticated en las tres tablas y concede solo lo
  que usa cada política (con privilegios por columna donde haga falta). anon no recibe nada.
- Todas las políticas: "to authenticated" y (select auth.uid()) envuelto en select (recomendación
  de rendimiento de Supabase). Una política por operación, con nombre descriptivo en español.
- perfiles: SELECT del propio perfil, de cualquier mentor (es un directorio de mentores) y de la
  contraparte de una sesión compartida. UPDATE solo del propio y solo de nombre y bio (el rol no
  se puede cambiar desde el cliente). Sin INSERT ni DELETE desde el cliente.
- sesiones: SELECT solo si eres mentor o estudiante de la sesión. INSERT solo como estudiante de
  la sesión, con estado pendiente y fecha futura. UPDATE de estado y fecha solo por participantes.
  Sin DELETE (se cancela, no se borra).
- mensajes: SELECT solo si participas en la sesión. INSERT solo si participas y
  remitente_id = auth.uid(). Sin UPDATE ni DELETE (el historial es inmutable).

# FORMATO DE SALIDA
1. Un único bloque ```sql con la migración completa, ordenada en secciones comentadas:
   tipos, tablas, índices, funciones y triggers, privilegios, RLS y políticas.
2. Debajo, una tabla Markdown "Política | Tabla | Operación | Regla" con todas las políticas.
3. Debajo, máximo 5 viñetas con riesgos o supuestos que yo deba revisar.
No expliques conceptos básicos de SQL. No inventes funciones de Supabase que no existan.
````
<!-- /INCLUIR -->

## 2.2 Prompt de refinamiento (texto exacto)

La primera respuesta cumplió casi todo: las 14 primeras comprobaciones pasaron. Falló la 15: el
estudiante podía poner su propia sesión en `confirmada`, porque el `UPDATE` de estado no tenía
reglas. La IA lo había advertido en sus riesgos. El refinamiento pide exactamente eso y prohíbe
tocar lo demás («Nada más cambia»), para no perder lo que ya estaba probado.

<!-- INCLUIR: ia/prompt-refinamiento-1.txt -->
````text
Revisé tu migración y la ejecuté en PostgreSQL 17 con una prueba de RLS de tres usuarios.
Pasaron 14 comprobaciones; falló esta: el estudiante pudo poner su propia sesión en
"confirmada" (UPDATE de estado sin reglas). Corrige solo lo siguiente y devuelve la migración
completa otra vez, en el mismo formato de salida (bloque sql, tabla de políticas, riesgos):

1. Máquina de estados en sesiones, con un trigger BEFORE UPDATE (security definer,
   set search_path = ''), errcode check_violation:
   - pendiente  -> confirmada : solo el mentor de la sesión
   - pendiente  -> cancelada  : cualquiera de los dos participantes
   - confirmada -> completada : solo el mentor
   - confirmada -> cancelada  : cualquiera de los dos
   - completada y cancelada son estados finales: no cambian.
   - Si cambia fecha: solo en pendiente o confirmada y siempre a futuro.
   - Cuando auth.uid() es null (service_role o SQL del dashboard) valida las transiciones, pero
     no quién las hace.
2. mensajes: solo se puede INSERTAR en sesiones en estado pendiente o confirmada (añádelo a la
   política de INSERT, no a un trigger).
3. Quita actualizado_en y su trigger de mensajes: los mensajes no se editan.
4. Nada más cambia: mismos nombres de tablas, tipos, políticas, privilegios e índices.
````
<!-- /INCLUIR -->

## 2.3 Qué cambió entre la respuesta 1 y la 2

Resultado de `diff` entre los dos bloques SQL:

| Cambio | Por qué |
|---|---|
| Nueva función y trigger `validar_transicion_sesion` | Máquina de estados: confirmar y completar solo el mentor, estados finales, fecha a futuro |
| Política de `INSERT` en `mensajes`: `s.estado in ('pendiente', 'confirmada')` | No se escribe en sesiones canceladas o completadas (prueba 24) |
| Quitados `mensajes.actualizado_en` y su trigger | Los mensajes no se editan |
| `revoke` de la nueva función | No se puede llamar desde la API |

Nada más cambió: mismas tablas, tipos, índices, privilegios y nombres de políticas.

## 2.4 Control del resultado

- Las restricciones del prompt se pueden comprobar una por una en el SQL (por ejemplo, `set
  search_path = ''` en las cuatro funciones y `to authenticated` en las siete políticas).
- El formato de salida pedido se cumplió en ambas respuestas: bloque SQL por secciones, tabla de
  políticas y cinco riesgos.
- La respuesta 2 se aplicó tal cual, con una sola corrección posterior hecha a mano tras auditarla
  (ver 2.5). Fuera de eso, la diferencia entre la respuesta 2 y la migración es el nombre de
  archivo de la línea 1: la migración lleva el timestamp real que dio `supabase migration new`.

## 2.5 Corrección tras la auditoría: el rol ya no sale de los metadatos

Una auditoría cruzada con una segunda batería de pruebas encontró un hueco que venía **del propio
prompt maestro**: pedía tomar el rol de `raw_user_meta_data->>'rol'`. Ese campo lo escribe el
cliente en `signUp({ options: { data } })`, así que cualquiera podía registrarse como `mentor`,
aparecer en el directorio y recibir y confirmar reservas. La IA cumplió la instrucción y lo
declaró como riesgo; el error de diseño era nuestro.

| Antes (respuesta 2) | Después (migración) |
|---|---|
| `handle_new_user` asigna `mentor` si los metadatos lo piden | `handle_new_user` inserta siempre `'estudiante'` |
| Riesgo aceptado: «autoasignación de rol» | Promover a mentor es administrativo: `update public.perfiles set rol = 'mentor'` con `service_role` (backend o SQL del Dashboard) |

La sonda que lo demostró quedó como prueba: la 01 de
[`supabase/pruebas/rls.sql`](../supabase/pruebas/rls.sql) y dos pruebas pgTAP de
[`supabase/tests/mentorlink_rls_test.sql`](../supabase/tests/mentorlink_rls_test.sql)
(«sonda del rol» y «service_role promueve a Ana a mentora»). `authenticated` sigue sin privilegio
`UPDATE` sobre `perfiles.rol` (prueba 12), así que nadie se promueve a sí mismo. Las respuestas de
la IA en [`ia/`](ia/) se conservan literales, con el comportamiento anterior.
