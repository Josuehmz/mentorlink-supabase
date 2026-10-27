-- Stub mínimo de lo que un proyecto de Supabase ya trae ANTES de cualquier migración.
-- Solo existe para ejecutar la migración y las pruebas de RLS en un PostgreSQL 17 normal
-- (Docker, imagen postgres:17-alpine) sin instalar la CLI de Supabase.
-- No forma parte del proyecto de Supabase: en un proyecto real todo esto ya existe.

-- Roles de la API de Supabase (PostgREST cambia a uno de ellos según el JWT).
create role anon          nologin noinherit;
create role authenticated nologin noinherit;
create role service_role  nologin noinherit bypassrls;

-- Esquema auth con lo que usan la migración y las pruebas.
create schema auth;

create table auth.users (
  id                 uuid primary key default gen_random_uuid(),
  email              text,
  raw_user_meta_data jsonb,
  created_at         timestamptz default now()
);

-- Misma definición que auth.uid() en Supabase: lee el "sub" del JWT de la petición.
create function auth.uid() returns uuid
language sql stable
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$$;

grant usage on schema public, auth to anon, authenticated, service_role;
grant execute on function auth.uid() to anon, authenticated, service_role;

-- Privilegios por defecto como en un proyecto de Supabase: cada tabla nueva de public
-- nace con TODO concedido a anon, authenticated y service_role. Por eso la migración revoca.
alter default privileges in schema public grant all on tables    to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
