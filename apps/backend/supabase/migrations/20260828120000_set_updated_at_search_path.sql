-- 20260828120000 — `set_updated_at` deja de tener el `search_path` mutable.
--
-- Lo señala el linter de Supabase (`function_search_path_mutable`, WARN) desde el Bloque 1, que es
-- cuando nació la función. Se arregla ahora, al cerrar el humo en producción de la Fase 4, porque
-- era el único aviso del advisor que sí es un aviso: los `rls_enabled_no_policy` son deny-all
-- deliberado, los dos `SECURITY DEFINER` ejecutables por `authenticated` (`activity_status` y
-- `touch_last_seen`) son su razón de ser, y el ERROR sobre `public_profiles` está decidido en el
-- ADR 0026.
--
-- QUÉ RIESGO CIERRA, QUE ES MENOR DE LO QUE SUGIERE EL AVISO
-- `set_updated_at` es SECURITY **INVOKER** (`pg_proc.prosecdef = false`), así que corre con los
-- permisos de quien dispara el trigger: un `search_path` manipulado no da escalada de privilegios,
-- que es lo que el aviso genérico da a entender. Lo que sí permite es que quien controle su propio
-- `search_path` interponga un `now()` en un esquema anterior y escriba un `updated_at` falso en la
-- fila que está tocando. Es poco, y aun así el arreglo es una línea.
--
-- POR QUÉ `= ''` Y NO `= 'public, pg_catalog'`
-- `pg_catalog` está siempre implícito y se busca antes que nada, así que `now()` resuelve igual con
-- el path vacío. La función no nombra ninguna tabla —solo `new.updated_at`, que es una variable de
-- registro del trigger—, de modo que no necesita ver ningún esquema. Un path vacío es la forma más
-- estricta que sigue funcionando, y hace que cualquier referencia futura sin cualificar falle en la
-- migración que la introduzca en vez de resolverse en un esquema inesperado.

alter function public.set_updated_at() set search_path = '';

-- rollback:
-- alter function public.set_updated_at() reset search_path;
