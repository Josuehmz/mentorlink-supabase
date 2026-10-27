-- =====================================================================
-- MentorLink · prueba de RLS, grants e integridad (pgTAP)
-- Archivo: supabase/tests/mentorlink_rls_test.sql
-- Correr:  supabase start && supabase db reset && supabase test db
--
-- Simula tres usuarios con `set local role authenticated` y
-- `set local request.jwt.claim.sub`, como indica la guía oficial de RLS:
--   M = mentor · E = estudiante de la sesión · I = estudiante ajeno (intruso)
-- Más un cuarto, O (oportunista), que se registra pidiendo rol "mentor": la sonda del rol.
-- Todo corre dentro de una transacción y termina en rollback: no deja datos.
-- Origen: las 39 pruebas de la versión B, adaptadas a esta migración, más 2 del rol (41).
-- =====================================================================
begin;
create extension if not exists pgtap with schema extensions;
select plan(41);

-- ---------------------------------------------------------------------
-- Datos de prueba (como postgres, que es quien corre la prueba)
-- Ana pide rol "mentor" en los metadatos, como lo haría signUp con options.data.
-- ---------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'ana@mentorlink.test',   '{"full_name": "Ana Mentora", "rol": "mentor"}'),
  ('22222222-2222-2222-2222-222222222222', 'bruno@mentorlink.test', '{"nombre": "Bruno Estudiante"}'),
  ('33333333-3333-3333-3333-333333333333', 'intruso@mentorlink.test', null),
  -- O: lo que guardaría GoTrue para signUp({ options: { data: { rol: 'mentor' } } }).
  -- (postgres no puede hacer `set role supabase_auth_admin` en Supabase local; el trigger es el
  -- mismo sea quien sea el que inserte en auth.users.)
  ('44444444-4444-4444-4444-444444444444', 'oportunista@mentorlink.test', '{"rol": "mentor"}');

-- ---------------------------------------------------------------------
-- Estructura: RLS, grants y forma de las políticas
-- ---------------------------------------------------------------------
select ok(
  (select bool_and(relrowsecurity) from pg_class
    where oid in ('public.perfiles'::regclass, 'public.sesiones'::regclass, 'public.mensajes'::regclass)),
  'RLS está activado en perfiles, sesiones y mensajes'
);
select ok(
  not (has_table_privilege('anon', 'public.perfiles', 'select,insert,update,delete')
    or has_table_privilege('anon', 'public.sesiones', 'select,insert,update,delete')
    or has_table_privilege('anon', 'public.mensajes', 'select,insert,update,delete')),
  'anon no tiene ningún grant sobre las tres tablas'
);
select ok(
  not has_column_privilege('authenticated', 'public.perfiles', 'rol', 'update'),
  'authenticated no puede actualizar la columna rol'
);
select ok(
  not exists (select 1 from pg_policies where schemaname = 'public' and roles <> '{authenticated}'),
  'todas las políticas están limitadas a authenticated'
);
select ok(
  not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      -- pg_policies guarda la expresión deparseada: (select auth.uid()) aparece como
      -- "( SELECT auth.uid() AS uid)". Toda aparición de auth.uid() debe ser de esa forma.
      and (   regexp_count(coalesce(qual, ''), 'auth\.uid\(\)')
           <> regexp_count(coalesce(qual, ''), 'SELECT auth\.uid\(\)')
           or regexp_count(coalesce(with_check, ''), 'auth\.uid\(\)')
           <> regexp_count(coalesce(with_check, ''), 'SELECT auth\.uid\(\)'))
  ),
  'toda llamada a auth.uid() en las políticas va envuelta en (select ...)'
);

-- ---------------------------------------------------------------------
-- Trigger handle_new_user
-- ---------------------------------------------------------------------
select results_eq(
  $$select nombre || ' / ' || rol from public.perfiles where id = '22222222-2222-2222-2222-222222222222'$$,
  array['Bruno Estudiante / estudiante'],
  'handle_new_user crea el perfil con el nombre de los metadatos y rol estudiante'
);
select results_eq(
  $$select nombre from public.perfiles where id = '33333333-3333-3333-3333-333333333333'$$,
  array['intruso'],
  'sin metadatos, el nombre sale de la parte local del correo'
);
-- Sonda del rol: pedir "mentor" en raw_user_meta_data no sirve.
select results_eq(
  $$select string_agg(nombre || ' / ' || rol, ', ' order by id) from public.perfiles
    where id in ('11111111-1111-1111-1111-111111111111', '44444444-4444-4444-4444-444444444444')$$,
  array['Ana Mentora / estudiante, oportunista / estudiante'],
  'sonda del rol: quien se registra pidiendo rol mentor nace estudiante'
);

-- Promover a mentor es administrativo: service_role (backend o SQL del Dashboard).
set local role service_role;
select results_eq(
  $$update public.perfiles set rol = 'mentor'
    where id = '11111111-1111-1111-1111-111111111111' returning rol::text$$,
  array['mentor'],
  'service_role promueve a Ana a mentora'
);
reset role;

-- ---------------------------------------------------------------------
-- anon: el grant falta, así que se detiene antes de cualquier política
-- ---------------------------------------------------------------------
set local role anon;
select throws_ok($$select * from public.sesiones$$, '42501', null, 'anon no puede leer sesiones');
select throws_ok($$select * from public.mensajes$$, '42501', null, 'anon no puede leer mensajes');

-- ---------------------------------------------------------------------
-- E (estudiante): agenda una sesión y escribe en ella
-- ---------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';

select results_eq(
  $$insert into public.sesiones (mentor_id, estudiante_id, fecha)
    values ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', now() + interval '2 days')
    returning estado::text$$,
  array['pendiente'],
  'el estudiante agenda una sesión consigo mismo como estudiante; nace pendiente'
);
select throws_ok(
  $$insert into public.sesiones (mentor_id, estudiante_id, fecha)
    values ('11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333333', now() + interval '2 days')$$,
  '42501', null,
  'el estudiante no puede agendar a nombre de otro estudiante'
);
select throws_ok(
  $$insert into public.sesiones (mentor_id, estudiante_id, fecha)
    values ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', now() - interval '1 day')$$,
  '42501', null,
  'no se puede agendar una sesión en el pasado'
);
select throws_ok(
  $$insert into public.sesiones (mentor_id, estudiante_id, fecha, estado)
    values ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', now() + interval '3 days', 'confirmada')$$,
  '42501', null,
  'el estudiante no puede crear una sesión ya confirmada'
);
select throws_ok(
  $$insert into public.sesiones (mentor_id, estudiante_id, fecha)
    values ('33333333-3333-3333-3333-333333333333', '22222222-2222-2222-2222-222222222222', now() + interval '2 days')$$,
  '23514', null,
  'mentor_id debe apuntar a un perfil con rol mentor (trigger)'
);
select results_eq(
  $$select nombre from public.perfiles where id = '11111111-1111-1111-1111-111111111111'$$,
  array['Ana Mentora'],
  'un estudiante ve el perfil de los mentores (directorio)'
);
select is_empty(
  $$select * from public.perfiles where id = '33333333-3333-3333-3333-333333333333'$$,
  'un estudiante no ve el perfil de otro estudiante ajeno'
);
select results_eq(
  $$update public.perfiles set bio = 'Aprendo Postgres'
    where id = '22222222-2222-2222-2222-222222222222' returning bio$$,
  array['Aprendo Postgres'],
  'el usuario edita su propia bio'
);
select throws_ok(
  $$update public.perfiles set rol = 'mentor' where id = '22222222-2222-2222-2222-222222222222'$$,
  '42501', null,
  'el usuario no puede ascenderse a mentor'
);
select is_empty(
  $$update public.perfiles set bio = 'hackeado'
    where id = '11111111-1111-1111-1111-111111111111' returning id$$,
  'el usuario no edita perfiles ajenos'
);
select results_eq(
  $$insert into public.mensajes (sesion_id, remitente_id, contenido)
    values ((select id from public.sesiones where estudiante_id = '22222222-2222-2222-2222-222222222222'),
            '22222222-2222-2222-2222-222222222222', 'Hola, Ana')
    returning contenido$$,
  array['Hola, Ana'],
  'el estudiante escribe en su sesión'
);
select throws_ok(
  $$insert into public.mensajes (sesion_id, remitente_id, contenido)
    values ((select id from public.sesiones where estudiante_id = '22222222-2222-2222-2222-222222222222'),
            '11111111-1111-1111-1111-111111111111', 'Mensaje suplantado')$$,
  '42501', null,
  'nadie escribe un mensaje a nombre de otro (remitente_id = auth.uid())'
);
select throws_ok($$update public.mensajes set contenido = 'editado'$$, '42501', null, 'los mensajes no se editan');
select throws_ok($$delete from public.mensajes$$, '42501', null, 'los mensajes no se borran');
select throws_ok($$delete from public.sesiones$$, '42501', null, 'las sesiones no se borran (se cancelan)');

-- ---------------------------------------------------------------------
-- M (mentor): ve la sesión y a su estudiante, confirma y responde
-- ---------------------------------------------------------------------
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

select results_eq(
  $$select estudiante_id::text from public.sesiones$$,
  array['22222222-2222-2222-2222-222222222222'],
  'el mentor ve la sesión en la que participa'
);
select results_eq(
  $$select nombre from public.perfiles where id = '22222222-2222-2222-2222-222222222222'$$,
  array['Bruno Estudiante'],
  'el mentor ve el perfil del estudiante con quien comparte sesión'
);
select results_eq(
  $$update public.sesiones set estado = 'confirmada' returning estado::text$$,
  array['confirmada'],
  'el mentor confirma la sesión'
);
select results_eq(
  $$insert into public.mensajes (sesion_id, remitente_id, contenido)
    values ((select id from public.sesiones limit 1), '11111111-1111-1111-1111-111111111111', 'Hola, Bruno')
    returning contenido$$,
  array['Hola, Bruno'],
  'el mentor responde en la sesión'
);
select results_eq(
  $$select count(*)::text from public.mensajes$$,
  array['2'],
  'el mentor lee los dos mensajes de su sesión'
);

-- ---------------------------------------------------------------------
-- I (intruso autenticado): tiene el grant, así que lo detiene la política
-- ---------------------------------------------------------------------
set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';

select is_empty($$select * from public.sesiones$$, 'un usuario ajeno no ve sesiones de otros');
select is_empty($$select * from public.mensajes$$, 'un usuario ajeno no lee mensajes de otros');
select is_empty(
  $$select * from public.perfiles where id = '22222222-2222-2222-2222-222222222222'$$,
  'un usuario ajeno no ve al estudiante de otra sesión'
);
select throws_ok(
  $$insert into public.mensajes (sesion_id, remitente_id, contenido)
    values ((select id from public.sesiones limit 1), '33333333-3333-3333-3333-333333333333', 'Me cuelo')$$,
  '42501', null,
  'un usuario ajeno no escribe en sesiones de otros'
);
select is_empty(
  $$update public.sesiones set estado = 'cancelada' returning id$$,
  'un usuario ajeno no cambia el estado de sesiones de otros'
);

-- ---------------------------------------------------------------------
-- Transiciones de estado (trigger): E solo puede cancelar
-- ---------------------------------------------------------------------
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';

select throws_ok(
  $$update public.sesiones set estado = 'completada'$$,
  '23514', null,
  'el estudiante no puede marcar la sesión como completada'
);
select results_eq(
  $$update public.sesiones set estado = 'cancelada' returning estado::text$$,
  array['cancelada'],
  'el estudiante puede cancelar su sesión'
);
select throws_ok(
  $$update public.sesiones set estado = 'pendiente'$$,
  '23514', null,
  'una sesión cancelada no se reabre'
);

-- ---------------------------------------------------------------------
-- Integridad también para roles privilegiados (que se saltan RLS)
-- ---------------------------------------------------------------------
reset role;
select throws_ok(
  $$insert into public.sesiones (mentor_id, estudiante_id, fecha)
    values ('22222222-2222-2222-2222-222222222222', '33333333-3333-3333-3333-333333333333', now() + interval '1 day')$$,
  '23514', null,
  'ni siquiera un rol privilegiado crea una sesión cuyo mentor no tiene rol mentor'
);
select throws_ok(
  $$insert into public.sesiones (mentor_id, estudiante_id, fecha)
    values ('11111111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', now() + interval '1 day')$$,
  '23514', null,
  'mentor y estudiante deben ser personas distintas'
);

select * from finish();
rollback;
