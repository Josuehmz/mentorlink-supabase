-- Datos de ejemplo para `supabase db reset` (se cargan después de las migraciones).
-- Dos usuarios: el trigger handle_new_user crea sus perfiles (nombre desde raw_user_meta_data).
-- Todo registro nace 'estudiante'; el rol de los metadatos se ignora. La mentora se promueve
-- después con un UPDATE, que es lo que haría un administrador con service_role.
-- Son usuarios de demostración sin contraseña: sirven para ver datos, no para iniciar sesión.
insert into auth.users (id, email, raw_user_meta_data) values
  ('aaaaaaaa-0000-4000-8000-000000000001', 'mentora.demo@ejemplo.com',
   '{"nombre": "Mentora Demo"}'),
  ('aaaaaaaa-0000-4000-8000-000000000002', 'estudiante.demo@ejemplo.com',
   '{"nombre": "Estudiante Demo"}');

-- Promoción administrativa a mentora (el seed corre como postgres).
update public.perfiles
set rol = 'mentor',
    bio = 'Arquitecta de software. Mentorías en bases de datos y Supabase.'
where id = 'aaaaaaaa-0000-4000-8000-000000000001';
