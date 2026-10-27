# 5. Auditoría IA: los cuatro ejes

La actividad se evalúa como una «Auditoría IA» con cuatro ejes. Esta tabla dice qué hay en el
repositorio para cada uno y en qué estado quedó.

| Eje | Qué hay en el repositorio | Estado |
|---|---|---|
| Análisis de código | La migración se ejecutó en PostgreSQL 17 y la revisaron 25 comprobaciones automáticas ([`supabase/pruebas/rls.sql`](../supabase/pruebas/rls.sql)). Las cuatro funciones usan `set search_path = ''` y nombres calificados; las de trigger no se pueden llamar desde la API | Verificado ([salida](evidencia/salida-pruebas-rls.txt)) |
| Optimización de prompts | Prompt maestro por bloques (rol, contexto, tarea, restricciones, seguridad, formato) y un refinamiento acotado que corrigió el único fallo sin tocar lo demás ([sección 2](02-prompts-ia.md)) | Dos iteraciones; la segunda pasó 25 de 25 |
| Tamaño de bundle | No aplica: este entregable es solo base de datos y configuración, no tiene front ni paquete JavaScript que medir | No aplica |
| Verificación RLS | RLS activo en las tres tablas, privilegios explícitos, siete políticas con `(select auth.uid())`, índices en las columnas de las políticas y prueba con cuatro usuarios, `anon` y `service_role` ([sección 1.6](01-esquema-y-rls.md#16-verificación)) | Verificado; la primera versión de la IA falló la prueba 15 y se corrigió |

Lo que no se pudo verificar: la CLI de Supabase y el inicio de sesión real con Google, porque no hay
CLI instalada ni proyecto de Supabase creado ([sección 3.1](03-cli-supabase.md#31-qué-es-real-y-qué-es-simulado)).
