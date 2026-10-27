-- supabase/migrations/20261027004403_inicializar_esquema.sql
-- MentorLink: esquema inicial (perfiles, sesiones, mensajes) con RLS y privilegios explícitos.

-- =====================================================================
-- 1. TIPOS
-- =====================================================================
create type public.rol_usuario as enum ('mentor', 'estudiante');
create type public.estado_sesion as enum ('pendiente', 'confirmada', 'completada', 'cancelada');

-- =====================================================================
-- 2. TABLAS
-- =====================================================================

-- perfiles.id: uuid porque es 1:1 con auth.users; on delete cascade: si se borra la cuenta, se borra el perfil.
create table public.perfiles (
  id             uuid primary key references auth.users (id) on delete cascade,
  nombre         text not null
                 check (char_length(btrim(nombre)) > 0 and char_length(nombre) <= 120),
  bio            text
                 check (bio is null or char_length(bio) <= 1000),
  rol            public.rol_usuario not null default 'estudiante',
  creado_en      timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);

create table public.sesiones (
  -- id: bigint identity; índices compactos y la enumeración la bloquea RLS, no la opacidad del id.
  id             bigint generated always as identity primary key,
  -- mentor_id: on delete cascade; borrar la cuenta del mentor elimina sus sesiones (no hay perfil al que apuntar).
  mentor_id      uuid not null references public.perfiles (id) on delete cascade,
  -- estudiante_id: on delete cascade; mismo criterio que mentor_id (las columnas son not null).
  estudiante_id  uuid not null references public.perfiles (id) on delete cascade,
  fecha          timestamptz not null,
  estado         public.estado_sesion not null default 'pendiente',
  creado_en      timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint sesiones_participantes_distintos check (mentor_id <> estudiante_id)
);

-- mensajes: sin actualizado_en; el historial es inmutable y no hay UPDATE.
create table public.mensajes (
  -- id: bigint identity; volumen alto, orden natural de inserción y RLS protege el acceso.
  id             bigint generated always as identity primary key,
  -- sesion_id: on delete cascade; un mensaje no tiene sentido sin su sesión.
  sesion_id      bigint not null references public.sesiones (id) on delete cascade,
  -- remitente_id: on delete cascade; el remitente es not null y su cuenta borrada arrastra sus mensajes.
  remitente_id   uuid not null references public.perfiles (id) on delete cascade,
  contenido      text not null
                 check (char_length(btrim(contenido)) > 0 and char_length(contenido) <= 2000),
  creado_en      timestamptz not null default now()
);

-- =====================================================================
-- 3. ÍNDICES (columnas FK usadas en políticas y joins)
-- =====================================================================
create index sesiones_mentor_id_idx      on public.sesiones (mentor_id);
create index sesiones_estudiante_id_idx  on public.sesiones (estudiante_id);
create index mensajes_sesion_id_idx      on public.mensajes (sesion_id, creado_en);
create index mensajes_remitente_id_idx   on public.mensajes (remitente_id);

-- =====================================================================
-- 4. FUNCIONES Y TRIGGERS
-- =====================================================================

-- 4.1 Mantener actualizado_en (solo perfiles y sesiones; mensajes no se editan)
create or replace function public.fijar_actualizado_en()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.actualizado_en := pg_catalog.now();
  return new;
end;
$$;

create trigger perfiles_fijar_actualizado_en
  before update on public.perfiles
  for each row execute function public.fijar_actualizado_en();

create trigger sesiones_fijar_actualizado_en
  before update on public.sesiones
  for each row execute function public.fijar_actualizado_en();

-- 4.2 Crear el perfil al registrarse (patrón oficial de Supabase)
--   El rol NO se toma de raw_user_meta_data: ese campo lo escribe el cliente en signUp
--   (options.data), así que cualquiera podría registrarse como mentor. Todo registro nace
--   'estudiante'; promover a mentor es una acción administrativa con service_role
--   (backend o SQL del Dashboard), porque authenticated no tiene UPDATE sobre perfiles.rol.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_meta   jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  v_nombre text;
begin
  v_nombre := coalesce(
    nullif(pg_catalog.btrim(v_meta ->> 'nombre'), ''),
    nullif(pg_catalog.btrim(v_meta ->> 'full_name'), ''),          -- Google OAuth
    nullif(pg_catalog.btrim(pg_catalog.split_part(new.email, '@', 1)), ''),
    'usuario'                                                        -- sin email (p. ej. teléfono)
  );
  v_nombre := pg_catalog.left(v_nombre, 120);

  insert into public.perfiles (id, nombre, rol)
  values (new.id, v_nombre, 'estudiante'::public.rol_usuario);

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 4.3 Validar roles de los participantes de una sesión (aplica también a service_role)
create or replace function public.validar_roles_sesion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.perfiles p
    where p.id = new.mentor_id and p.rol = 'mentor'::public.rol_usuario
  ) then
    raise exception 'mentor_id (%) no corresponde a un perfil con rol mentor', new.mentor_id
      using errcode = 'check_violation';
  end if;

  if not exists (
    select 1 from public.perfiles p
    where p.id = new.estudiante_id and p.rol = 'estudiante'::public.rol_usuario
  ) then
    raise exception 'estudiante_id (%) no corresponde a un perfil con rol estudiante', new.estudiante_id
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

create trigger sesiones_validar_roles
  before insert or update of mentor_id, estudiante_id on public.sesiones
  for each row execute function public.validar_roles_sesion();

-- 4.4 Máquina de estados de sesiones (aplica también a service_role).
--   pendiente  -> confirmada : solo el mentor
--   pendiente  -> cancelada  : cualquiera de los dos participantes
--   confirmada -> completada : solo el mentor
--   confirmada -> cancelada  : cualquiera de los dos
--   completada y cancelada   : finales, no cambian
--   fecha: solo cambia en pendiente o confirmada, y siempre a futuro.
--   Con auth.uid() null (service_role, SQL del dashboard) se validan las transiciones, no el actor.
create or replace function public.validar_transicion_sesion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  -- Estados finales: ni estado ni fecha pueden cambiar.
  if old.estado in ('completada'::public.estado_sesion, 'cancelada'::public.estado_sesion)
     and (new.estado is distinct from old.estado or new.fecha is distinct from old.fecha) then
    raise exception 'la sesión % está en estado final (%) y no puede cambiar', old.id, old.estado
      using errcode = 'check_violation';
  end if;

  -- Transiciones de estado.
  if new.estado is distinct from old.estado then
    if old.estado = 'pendiente'::public.estado_sesion
       and new.estado = 'confirmada'::public.estado_sesion then
      if v_uid is not null and v_uid <> old.mentor_id then
        raise exception 'solo el mentor puede confirmar la sesión %', old.id
          using errcode = 'check_violation';
      end if;

    elsif old.estado = 'confirmada'::public.estado_sesion
          and new.estado = 'completada'::public.estado_sesion then
      if v_uid is not null and v_uid <> old.mentor_id then
        raise exception 'solo el mentor puede completar la sesión %', old.id
          using errcode = 'check_violation';
      end if;

    elsif old.estado in ('pendiente'::public.estado_sesion, 'confirmada'::public.estado_sesion)
          and new.estado = 'cancelada'::public.estado_sesion then
      -- Cualquiera de los dos participantes; la política de UPDATE ya exige participar.
      null;

    else
      raise exception 'transición de estado no permitida en la sesión %: % -> %',
        old.id, old.estado, new.estado
        using errcode = 'check_violation';
    end if;
  end if;

  -- Cambio de fecha: solo en pendiente o confirmada y a futuro.
  if new.fecha is distinct from old.fecha then
    if old.estado not in ('pendiente'::public.estado_sesion, 'confirmada'::public.estado_sesion) then
      raise exception 'la fecha de la sesión % solo cambia en pendiente o confirmada', old.id
        using errcode = 'check_violation';
    end if;
    if new.fecha <= pg_catalog.now() then
      raise exception 'la nueva fecha de la sesión % debe ser futura', old.id
        using errcode = 'check_violation';
    end if;
  end if;

  return new;
end;
$$;

create trigger sesiones_validar_transicion
  before update of estado, fecha on public.sesiones
  for each row execute function public.validar_transicion_sesion();

-- Las funciones de trigger no deben poder invocarse desde la API.
revoke all on function public.fijar_actualizado_en()       from public, anon, authenticated;
revoke all on function public.handle_new_user()            from public, anon, authenticated;
revoke all on function public.validar_roles_sesion()       from public, anon, authenticated;
revoke all on function public.validar_transicion_sesion()  from public, anon, authenticated;

-- =====================================================================
-- 5. PRIVILEGIOS
-- =====================================================================
revoke all on table public.perfiles from public, anon, authenticated;
revoke all on table public.sesiones from public, anon, authenticated;
revoke all on table public.mensajes from public, anon, authenticated;

-- perfiles: lectura y edición de nombre y bio (rol no editable).
grant select                 on table public.perfiles to authenticated;
grant update (nombre, bio)   on table public.perfiles to authenticated;

-- sesiones: lectura, alta (sin id ni auditoría) y cambio de estado y fecha.
grant select                                            on table public.sesiones to authenticated;
grant insert (mentor_id, estudiante_id, fecha, estado)  on table public.sesiones to authenticated;
grant update (estado, fecha)                            on table public.sesiones to authenticated;

-- mensajes: lectura y alta; sin update ni delete.
grant select                                      on table public.mensajes to authenticated;
grant insert (sesion_id, remitente_id, contenido) on table public.mensajes to authenticated;

-- =====================================================================
-- 6. RLS Y POLÍTICAS
-- =====================================================================
alter table public.perfiles enable row level security;
alter table public.sesiones enable row level security;
alter table public.mensajes enable row level security;

-- ---------- perfiles ----------
create policy "perfiles: ver propio, mentores y contrapartes de sesión"
  on public.perfiles
  for select
  to authenticated
  using (
    id = (select auth.uid())
    or rol = 'mentor'::public.rol_usuario
    or exists (
      select 1
      from public.sesiones s
      where (s.mentor_id = (select auth.uid()) and s.estudiante_id = perfiles.id)
         or (s.estudiante_id = (select auth.uid()) and s.mentor_id = perfiles.id)
    )
  );

create policy "perfiles: editar solo el propio"
  on public.perfiles
  for update
  to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- ---------- sesiones ----------
create policy "sesiones: ver solo como participante"
  on public.sesiones
  for select
  to authenticated
  using ((select auth.uid()) in (mentor_id, estudiante_id));

create policy "sesiones: solicitar como estudiante, pendiente y a futuro"
  on public.sesiones
  for insert
  to authenticated
  with check (
    estudiante_id = (select auth.uid())
    and estado = 'pendiente'::public.estado_sesion
    and fecha > now()
  );

-- Quién puede hacer cada transición lo decide el trigger sesiones_validar_transicion.
create policy "sesiones: actualizar estado y fecha solo participantes"
  on public.sesiones
  for update
  to authenticated
  using ((select auth.uid()) in (mentor_id, estudiante_id))
  with check ((select auth.uid()) in (mentor_id, estudiante_id));

-- ---------- mensajes ----------
create policy "mensajes: ver solo si participas en la sesión"
  on public.mensajes
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.sesiones s
      where s.id = mensajes.sesion_id
        and (select auth.uid()) in (s.mentor_id, s.estudiante_id)
    )
  );

create policy "mensajes: enviar como participante y remitente propio"
  on public.mensajes
  for insert
  to authenticated
  with check (
    remitente_id = (select auth.uid())
    and exists (
      select 1
      from public.sesiones s
      where s.id = mensajes.sesion_id
        and (select auth.uid()) in (s.mentor_id, s.estudiante_id)
        and s.estado in ('pendiente'::public.estado_sesion, 'confirmada'::public.estado_sesion)
    )
  );
