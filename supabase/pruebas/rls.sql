-- Prueba de las políticas RLS de MentorLink.
--
-- Simula tres usuarios reales con `set local role authenticated` y
-- `set local request.jwt.claims`, que es lo mismo que hace la API de Supabase con cada JWT.
-- Todo corre dentro de una transacción que termina en ROLLBACK: no deja datos.
--
-- Cómo correrla:
--   Con Supabase local:  psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -v ON_ERROR_STOP=1 -f supabase/pruebas/rls.sql
--   Sin Supabase (como se hizo en este repositorio): bash pruebas-locales/ejecutar-pruebas.sh
-- Cada comprobación imprime "OK NN ..." ; si una falla, se detiene con "FALLO NN ...".
--
-- Usuarios de la prueba (uuid fijos):
--   Ana   11111111-...  mentora
--   Beto  22222222-...  estudiante, dueño de la sesión
--   Carla 33333333-...  estudiante ajena (intrusa); se registra pidiendo rol "admin"
--   Dario 44444444-...  segundo mentor, sin sesiones

\set ON_ERROR_STOP on
begin;

-- ============================================================
-- Datos: el registro en auth.users dispara handle_new_user
-- ============================================================
insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'ana@ejemplo.com',   '{"nombre": "Ana Mentora", "rol": "mentor"}'),
  ('22222222-2222-2222-2222-222222222222', 'beto@ejemplo.com',  '{"full_name": "Beto Estudiante"}'),
  ('33333333-3333-3333-3333-333333333333', 'carla@ejemplo.com', '{"rol": "admin"}'),
  ('44444444-4444-4444-4444-444444444444', 'dario@ejemplo.com', '{"nombre": "Dario Mentor", "rol": "mentor"}');

do $$
begin
  if (select rol from public.perfiles where id = '11111111-1111-1111-1111-111111111111') <> 'mentor' then
    raise exception 'FALLO 01: Ana debía quedar como mentor'; end if;
  if (select nombre from public.perfiles where id = '22222222-2222-2222-2222-222222222222') <> 'Beto Estudiante' then
    raise exception 'FALLO 01: el nombre de Google (full_name) no se tomó'; end if;
  if (select rol::text || '/' || nombre from public.perfiles where id = '33333333-3333-3333-3333-333333333333') <> 'estudiante/carla' then
    raise exception 'FALLO 01: un rol inválido debía caer en estudiante y el nombre en la parte local del email'; end if;
  raise notice 'OK 01 handle_new_user crea los 4 perfiles con rol y nombre correctos (rol "admin" -> estudiante)';
end $$;

-- ============================================================
-- anon: sin sesión no se lee nada
-- ============================================================
set local role anon;
do $$
begin
  begin
    perform 1 from public.perfiles;
    raise exception 'FALLO 02: anon pudo leer perfiles';
  exception when insufficient_privilege then
    raise notice 'OK 02 anon no tiene privilegios sobre perfiles (permission denied)';
  end;
  begin
    perform 1 from public.mensajes;
    raise exception 'FALLO 02: anon pudo leer mensajes';
  exception when insufficient_privilege then
    raise notice 'OK 02 anon no tiene privilegios sobre mensajes (permission denied)';
  end;
end $$;
reset role;

-- ============================================================
-- Beto (estudiante): directorio de mentores y solicitud de sesión
-- ============================================================
set local role authenticated;
set local request.jwt.claims = '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';

do $$
declare n int;
begin
  select count(*) into n from public.perfiles;
  if n <> 3 then raise exception 'FALLO 03: Beto debía ver 3 perfiles (él y los 2 mentores) y ve %', n; end if;
  if exists (select 1 from public.perfiles where id = '33333333-3333-3333-3333-333333333333') then
    raise exception 'FALLO 03: Beto ve el perfil de otra estudiante'; end if;
  raise notice 'OK 03 Beto ve su perfil y el directorio de mentores, no a otros estudiantes';
end $$;

do $$
begin
  insert into public.sesiones (mentor_id, estudiante_id, fecha)
  values ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', now() + interval '2 days');
  raise notice 'OK 04 Beto solicita una sesión con Ana (pendiente, fecha futura)';
end $$;

do $$
begin
  begin
    insert into public.sesiones (mentor_id, estudiante_id, fecha)
    values ('11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333333', now() + interval '2 days');
    raise exception 'FALLO 05: Beto creó una sesión a nombre de Carla';
  exception when insufficient_privilege then
    raise notice 'OK 05 Beto no puede crear sesiones a nombre de otra estudiante (RLS)';
  end;
  begin
    insert into public.sesiones (mentor_id, estudiante_id, fecha)
    values ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', now() - interval '1 day');
    raise exception 'FALLO 06: Beto creó una sesión en el pasado';
  exception when insufficient_privilege then
    raise notice 'OK 06 no se puede solicitar una sesión con fecha pasada (RLS)';
  end;
  begin
    insert into public.sesiones (mentor_id, estudiante_id, fecha, estado)
    values ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', now() + interval '3 days', 'confirmada');
    raise exception 'FALLO 07: Beto creó una sesión ya confirmada';
  exception when insufficient_privilege then
    raise notice 'OK 07 una sesión nueva solo puede nacer pendiente (RLS)';
  end;
  begin
    insert into public.sesiones (mentor_id, estudiante_id, fecha)
    values ('33333333-3333-3333-3333-333333333333', '22222222-2222-2222-2222-222222222222', now() + interval '2 days');
    raise exception 'FALLO 08: se aceptó como mentor a un perfil con rol estudiante';
  exception when check_violation then
    raise notice 'OK 08 mentor_id debe tener rol mentor (trigger validar_roles_sesion)';
  end;
end $$;

do $$
declare v_sesion bigint;
begin
  select id into v_sesion from public.sesiones;
  insert into public.mensajes (sesion_id, remitente_id, contenido)
  values (v_sesion, '22222222-2222-2222-2222-222222222222', 'Hola Ana, quiero repasar RLS.');
  raise notice 'OK 09 Beto escribe en su sesión';
  begin
    insert into public.mensajes (sesion_id, remitente_id, contenido)
    values (v_sesion, '11111111-1111-1111-1111-111111111111', 'Mensaje suplantando a Ana');
    raise exception 'FALLO 10: Beto envió un mensaje como Ana';
  exception when insufficient_privilege then
    raise notice 'OK 10 nadie puede enviar mensajes con otro remitente_id (RLS)';
  end;
  begin
    insert into public.mensajes (sesion_id, remitente_id, contenido)
    values (v_sesion, '22222222-2222-2222-2222-222222222222', '   ');
    raise exception 'FALLO 11: se aceptó un mensaje vacío';
  exception when check_violation then
    raise notice 'OK 11 un mensaje vacío lo rechaza el check de contenido';
  end;
end $$;

do $$
declare n int;
begin
  begin
    update public.perfiles set rol = 'mentor' where id = '22222222-2222-2222-2222-222222222222';
    raise exception 'FALLO 12: Beto cambió su propio rol';
  exception when insufficient_privilege then
    raise notice 'OK 12 nadie puede cambiar su rol desde el cliente (privilegio por columna)';
  end;
  update public.perfiles set bio = 'Estudiante de sistemas' where id = '22222222-2222-2222-2222-222222222222';
  update public.perfiles set bio = 'editado por Beto' where id = '11111111-1111-1111-1111-111111111111';
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'FALLO 13: Beto editó el perfil de Ana'; end if;
  raise notice 'OK 13 Beto edita su bio y no la de Ana (0 filas)';
  begin
    update public.mensajes set contenido = 'editado';
    raise exception 'FALLO 14: se pudo editar un mensaje';
  exception when insufficient_privilege then
    raise notice 'OK 14 los mensajes no se editan (sin privilegio UPDATE)';
  end;
  begin
    delete from public.mensajes;
    raise exception 'FALLO 14: se pudo borrar un mensaje';
  exception when insufficient_privilege then
    raise notice 'OK 14 los mensajes no se borran (sin privilegio DELETE)';
  end;
  begin
    delete from public.sesiones;
    raise exception 'FALLO 14: se pudo borrar una sesión';
  exception when insufficient_privilege then
    raise notice 'OK 14 las sesiones no se borran, se cancelan (sin privilegio DELETE)';
  end;
  begin
    update public.sesiones set estado = 'confirmada';
    raise exception 'FALLO 15: el estudiante confirmó su propia sesión';
  exception when check_violation then
    raise notice 'OK 15 el estudiante no puede confirmar la sesión (trigger de transiciones)';
  end;
end $$;
reset role;

-- ============================================================
-- Ana (mentora): ve su sesión, a su estudiante y confirma
-- ============================================================
set local role authenticated;
set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';

do $$
begin
  if (select count(*) from public.sesiones) <> 1 then raise exception 'FALLO 16: Ana debía ver 1 sesión'; end if;
  if (select count(*) from public.mensajes) <> 1 then raise exception 'FALLO 16: Ana debía ver 1 mensaje'; end if;
  if not exists (select 1 from public.perfiles where id = '22222222-2222-2222-2222-222222222222') then
    raise exception 'FALLO 16: Ana no ve el perfil de su estudiante'; end if;
  if exists (select 1 from public.perfiles where id = '33333333-3333-3333-3333-333333333333') then
    raise exception 'FALLO 16: Ana ve a una estudiante con la que no tiene sesión'; end if;
  raise notice 'OK 16 Ana ve su sesión, su mensaje y a Beto (contraparte), no a Carla';
  update public.sesiones set estado = 'confirmada';
  raise notice 'OK 17 la mentora confirma la sesión (pendiente -> confirmada)';
  insert into public.mensajes (sesion_id, remitente_id, contenido)
  select id, '11111111-1111-1111-1111-111111111111', 'Confirmada. Nos vemos.' from public.sesiones;
  raise notice 'OK 18 Ana responde en la sesión';
end $$;
reset role;

-- ============================================================
-- Carla (estudiante ajena): no ve ni toca nada de la sesión
-- ============================================================
-- Simula que Carla conoce el id de la sesión de Beto por fuera (p. ej. adivinándolo).
create temp table id_filtrado on commit drop as select id from public.sesiones;
grant select on id_filtrado to authenticated;
set local role authenticated;
set local request.jwt.claims = '{"sub": "33333333-3333-3333-3333-333333333333", "role": "authenticated"}';

do $$
declare n int;
begin
  if (select count(*) from public.sesiones) <> 0 then raise exception 'FALLO 19: Carla ve sesiones ajenas'; end if;
  if (select count(*) from public.mensajes) <> 0 then raise exception 'FALLO 19: Carla ve mensajes ajenos'; end if;
  if exists (select 1 from public.perfiles where id = '22222222-2222-2222-2222-222222222222') then
    raise exception 'FALLO 19: Carla ve el perfil de Beto'; end if;
  raise notice 'OK 19 Carla ve 0 sesiones, 0 mensajes y no ve a Beto';
  update public.sesiones set estado = 'cancelada';
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'FALLO 20: Carla canceló una sesión ajena'; end if;
  raise notice 'OK 20 Carla no puede modificar la sesión ajena (0 filas)';
  begin
    insert into public.mensajes (sesion_id, remitente_id, contenido)
    select id, '33333333-3333-3333-3333-333333333333', 'Me cuelo en la sesión' from id_filtrado;
    raise exception 'FALLO 21: Carla escribió en una sesión ajena';
  exception when insufficient_privilege then
    raise notice 'OK 21 Carla no puede escribir en una sesión ajena aunque adivine el id (RLS)';
  end;
end $$;
reset role;

-- ============================================================
-- Beto cancela; una sesión cancelada es final y ya no admite mensajes
-- ============================================================
set local role authenticated;
set local request.jwt.claims = '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';

do $$
begin
  update public.sesiones set estado = 'cancelada';
  raise notice 'OK 22 un participante cancela la sesión (confirmada -> cancelada)';
  begin
    update public.sesiones set estado = 'pendiente';
    raise exception 'FALLO 23: se reabrió una sesión cancelada';
  exception when check_violation then
    raise notice 'OK 23 una sesión cancelada no se reabre (estado final)';
  end;
  begin
    insert into public.mensajes (sesion_id, remitente_id, contenido)
    select id, '22222222-2222-2222-2222-222222222222', 'Mensaje tardío' from public.sesiones;
    raise exception 'FALLO 24: se escribió en una sesión cancelada';
  exception when insufficient_privilege then
    raise notice 'OK 24 no se escribe en sesiones canceladas o completadas (RLS)';
  end;
end $$;
reset role;

-- ============================================================
-- service_role se salta RLS, pero no las reglas de los triggers
-- ============================================================
set local role service_role;
do $$
begin
  begin
    insert into public.sesiones (mentor_id, estudiante_id, fecha)
    values ('22222222-2222-2222-2222-222222222222', '33333333-3333-3333-3333-333333333333', now() + interval '1 day');
    raise exception 'FALLO 25: service_role creó una sesión entre dos estudiantes';
  exception when check_violation then
    raise notice 'OK 25 la regla de roles también aplica a service_role (trigger)';
  end;
end $$;
reset role;

do $$ begin raise notice 'TODAS LAS PRUEBAS DE RLS PASARON'; end $$;
rollback;
