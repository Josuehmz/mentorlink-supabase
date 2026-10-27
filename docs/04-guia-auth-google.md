# 4. Guía de configuración de Auth: Email/Password y Google

MentorLink permite entrar con correo y contraseña o con la cuenta de Google. Ambos métodos crean
una fila en `auth.users`, y el trigger `handle_new_user` le crea el perfil
([sección 1.5](01-esquema-y-rls.md#15-reglas-en-triggers)); con Google, el nombre sale del campo
`full_name` que entrega Google. Todo lo de esta guía se configura en el Dashboard de Supabase.
**Ningún valor de esta guía es real**: `<project-ref>`, el Client ID y el Client Secret son
marcadores, y el Client Secret nunca va en el código ni en el repositorio.

## 4.1 Email/Password

En el Dashboard: **Authentication → Sign In / Providers → Email**.

| Ajuste | Valor | Por qué |
|---|---|---|
| Enable Email provider | Activado | Método base de registro |
| Confirm email | Activado | El usuario confirma su correo antes de entrar; evita cuentas con correos ajenos |
| Secure email change | Activado | Un cambio de correo se confirma en el correo viejo y en el nuevo |
| Minimum password length | 8 o más | Menos de 8 no es recomendable según Supabase |
| Password requirements | Letras minúsculas, mayúsculas, dígitos y símbolos | Amplía el espacio de contraseñas |
| Leaked password protection | Activado si el plan lo permite | Rechaza contraseñas filtradas (HaveIBeenPwned); solo en plan Pro o superior |

Para producción hace falta un SMTP propio en **Authentication → Emails → SMTP Settings**: el SMTP que
trae Supabase solo envía a direcciones del equipo del proyecto y tiene un límite bajo de mensajes
por hora, así que los correos de confirmación no llegarían a los estudiantes.

Uso desde el cliente:

```js
await supabase.auth.signUp({
  email: 'estudiante@ejemplo.com',
  password: '<contraseña>',
  options: { data: { nombre: 'Nombre Apellido', rol: 'estudiante' } }, // lo lee handle_new_user
})
await supabase.auth.signInWithPassword({ email: 'estudiante@ejemplo.com', password: '<contraseña>' })
```

## 4.2 Google OAuth en 3 pasos

### Paso 1. Google Cloud Console: pantalla de consentimiento y credencial OAuth

1. En https://console.cloud.google.com crea o elige un proyecto.
2. En **Google Auth Platform** configura la pantalla de consentimiento: nombre de la app (MentorLink),
   correo de soporte, público (**Audience**: externo) y en **Data Access** los alcances `openid`,
   `.../auth/userinfo.email` y `.../auth/userinfo.profile`.
3. En **Clients → Create client** elige el tipo **Web application** y llena:
   - **Authorized JavaScript origins:** la URL de la app, por ejemplo `https://mentorlink.ejemplo.com`
     (y `http://localhost:3000` para desarrollo).
   - **Authorized redirect URIs:** `https://<project-ref>.supabase.co/auth/v1/callback`
     (la URL exacta aparece en el paso 2, en la página del proveedor Google del Dashboard).
4. Al crear el cliente, Google muestra el **Client ID** y el **Client Secret**. Guárdalos en un
   gestor de secretos, no en el repositorio.

### Paso 2. Dashboard de Supabase: activar el proveedor Google

1. **Authentication → Sign In / Providers → Google**.
2. Activa **Enable Sign in with Google**.
3. Pega el **Client ID** y el **Client Secret** del paso 1.
4. Copia la **Callback URL (for OAuth)** que muestra esta página y confirma que es la misma que
   pusiste en *Authorized redirect URIs* en Google. Guarda.

### Paso 3. URL Configuration y prueba con `signInWithOAuth`

1. **Authentication → URL Configuration**:
   - **Site URL:** la URL de producción, por ejemplo `https://mentorlink.ejemplo.com`
     (es la redirección por defecto y la base de los enlaces de los correos).
   - **Redirect URLs:** las URLs permitidas para `redirectTo`, por ejemplo
     `https://mentorlink.ejemplo.com/auth/callback` y `http://localhost:3000/**` para desarrollo.
2. Prueba desde el cliente:

```js
const { error } = await supabase.auth.signInWithOAuth({
  provider: 'google',
  options: { redirectTo: 'https://mentorlink.ejemplo.com/auth/callback' },
})
```

3. Comprueba el resultado: el usuario aparece en **Authentication → Users** con proveedor `google`
   y en `public.perfiles` con su nombre de Google y rol `estudiante`.

## 4.3 Lo mismo en local (`supabase/config.toml`)

Para `supabase start`, estas claves van en el `config.toml` que genera `supabase init`
(fragmento; el secreto se lee de una variable de entorno, nunca se escribe en el archivo):

```toml
[auth]
site_url = "http://127.0.0.1:3000"
additional_redirect_urls = ["http://127.0.0.1:3000/auth/callback"]

[auth.email]
enable_signup = true
enable_confirmations = true
double_confirm_changes = true

[auth.external.google]
enabled = true
client_id = "env(SUPABASE_AUTH_EXTERNAL_GOOGLE_CLIENT_ID)"
secret = "env(SUPABASE_AUTH_EXTERNAL_GOOGLE_SECRET)"
```

En local, el redirect autorizado en Google es `http://127.0.0.1:54321/auth/v1/callback`.
Las variables van en un `.env` que no se sube (ver [`.env.example`](../.env.example)).
Este fragmento no se probó con la CLI (no está instalada); las claves son las de la referencia de
configuración.

## Fuentes

- Sign in with Google: https://supabase.com/docs/guides/auth/social-login/auth-google
- Redirect URLs: https://supabase.com/docs/guides/auth/redirect-urls
- Seguridad de contraseñas: https://supabase.com/docs/guides/auth/password-security
- SMTP propio: https://supabase.com/docs/guides/auth/auth-smtp
- Referencia de `config.toml`: https://supabase.com/docs/guides/local-development/cli/config
