/// Contrato del punto de actividad (`RN-30`, `RN-32`).
///
/// ## Lo que este contrato NO puede devolver, por diseño
///
/// **Nunca una marca de tiempo.** El RPC `activity_status` devuelve un **booleano** y nada más: ni
/// el `last_seen_at`, ni «hace N minutos», ni la marca redondeada. `last_seen_at` vive en
/// `profiles_private` justo para que `grant select on public.profiles` no la exponga, y esta
/// interfaz mantiene esa frontera — un `Future<DateTime?>` aquí desharía la migración entera.
///
/// **`RN-32` es recíproco y vive dentro del RPC**, no aquí: quien oculta su actividad tampoco ve la
/// de los demás. Si estuviera en esta capa bastaría una llamada directa al RPC —que cualquier
/// `authenticated` puede hacer— para saltárselo.
///
/// Propiedad que conviene no perder: un uuid inexistente y uno de alguien inactivo devuelven
/// **exactamente lo mismo** (`false`), así que esto no sirve para averiguar si una cuenta existe.
abstract interface class ActivityRepository {
  /// Latido: escribe `now()` en el `last_seen_at` propio (`touch_last_seen`).
  ///
  /// El RPC **no acepta parámetros**, y eso es la garantía de que nadie puede latir por otro ni
  /// fingir una hora. Sin sesión no actualiza nada y **no da error** (falla cerrado).
  Future<void> heartbeat();

  /// Si cada uno de [userIds] está activo ahora mismo.
  ///
  /// **Máximo 500 ids por llamada**: por encima, el RPC lanza excepción en vez de truncar en
  /// silencio — devolver menos filas de las pedidas haría pintar puntos grises sin saber por qué.
  /// Las pantallas que lo usan paginan muy por debajo de esa cota (la bandeja tope a 100).
  ///
  /// Los ids que no aparezcan en la respuesta se tratan como `false`.
  Future<Map<String, bool>> activeStatus(List<String> userIds);
}
