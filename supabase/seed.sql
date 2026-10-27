-- Datos de ejemplo para `supabase db reset` (se cargan después de las migraciones).
-- Dos usuarios: el trigger handle_new_user crea sus perfiles a partir de raw_user_meta_data.
-- Son usuarios de demostración sin contraseña: sirven para ver datos, no para iniciar sesión.
insert into auth.users (id, email, raw_user_meta_data) values
  ('aaaaaaaa-0000-4000-8000-000000000001', 'mentora.demo@ejemplo.com',
   '{"nombre": "Mentora Demo", "rol": "mentor"}'),
  ('aaaaaaaa-0000-4000-8000-000000000002', 'estudiante.demo@ejemplo.com',
   '{"nombre": "Estudiante Demo", "rol": "estudiante"}');

update public.perfiles
set bio = 'Arquitecta de software. Mentorías en bases de datos y Supabase.'
where id = 'aaaaaaaa-0000-4000-8000-000000000001';
