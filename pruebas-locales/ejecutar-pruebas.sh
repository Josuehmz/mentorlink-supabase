#!/usr/bin/env bash
# Ejecuta la migración y las pruebas de RLS en un PostgreSQL 17 desechable (Docker).
# No instala nada: usa la imagen postgres:17-alpine y la borra al terminar.
#
#   bash pruebas-locales/ejecutar-pruebas.sh                 # migración de supabase/migrations
#   bash pruebas-locales/ejecutar-pruebas.sh otra.sql        # otra migración (p. ej. una versión anterior)
#
# Orden: stub de Supabase -> migración -> seed (en transacción revertida) -> supabase/pruebas/rls.sql
set -euo pipefail
cd "$(dirname "$0")/.."

MIGRACION="${1:-$(printf '%s\n' supabase/migrations/*_inicializar_esquema.sql | tail -1)}"
NOMBRE="mentorlink-pruebas-$$"

docker run -d --rm --name "$NOMBRE" -e POSTGRES_PASSWORD=postgres postgres:17-alpine >/dev/null
trap 'docker rm -f "$NOMBRE" >/dev/null 2>&1 || true' EXIT

# El servidor temporal de initdb solo escucha por socket; esperar a TCP evita conectarse a él.
for _ in $(seq 1 60); do
  docker exec "$NOMBRE" psql -U postgres -h 127.0.0.1 -tAc 'select 1' >/dev/null 2>&1 && break
  sleep 1
done

psql_c() { docker exec -i "$NOMBRE" psql -U postgres -h 127.0.0.1 -v ON_ERROR_STOP=1 -q "$@"; }

echo "== Servidor: $(psql_c -tAc 'select version()')"
echo "== 1. Stub de Supabase (roles, auth.users, auth.uid(), privilegios por defecto)"
psql_c < pruebas-locales/stub-supabase.sql
echo "== 2. Migración: $MIGRACION"
psql_c < "$MIGRACION"
echo "   tablas: $(psql_c -tAc "select string_agg(tablename || ' (rls=' || rowsecurity || ')', ', ' order by tablename) from pg_tables where schemaname = 'public'")"
echo "   políticas: $(psql_c -tAc "select count(*) from pg_policies where schemaname = 'public'")"
echo "== 3. Seed (dentro de una transacción revertida)"
{ echo 'begin;'; cat supabase/seed.sql; echo "select 'perfiles creados por el seed: ' || count(*) from public.perfiles;"; echo 'rollback;'; } \
  | psql_c -tA
echo "== 4. Pruebas de RLS: supabase/pruebas/rls.sql"
psql_c < supabase/pruebas/rls.sql 2>&1 | sed -E 's/^psql:<stdin>:[0-9]+: //'
