import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/supabase/supabase_providers.dart';

/// Marca «he estado aquí» — `RN-30`, paso 4 de la Tarea 24.
///
/// ## Al arrancar y al volver a primer plano. NUNCA en un temporizador
///
/// El plan lo dice con esas palabras, y el motivo es de coste y de privacidad a la vez. Un
/// temporizador de un minuto son ~1.400 escrituras por usuario y día contra `profiles_private`, para
/// un dato cuya única lectura devuelve un **booleano**: el punto verde de `RN-30` no distingue «hace
/// 30 segundos» de «hace 4 minutos». Y una traza de presencia con resolución de minuto es un mapa de
/// cuándo duerme cada persona, que es exactamente lo que `activity_status` existe para no emitir.
///
/// Dos disparos, entonces: al montar la app y en cada `AppLifecycleState.resumed`. Es lo que hace
/// falta para que el punto sea cierto cuando alguien lo mira.
///
/// ## Un latido que falla no puede tirar nada
///
/// `touch_last_seen` es cosmético: si la red se cae, lo que pasa es que el punto de alguien se
/// apaga antes de tiempo. Que eso reventara la app —o siquiera enseñara un error— sería
/// desproporcionado, así que se traga el fallo a propósito.
class ActivityHeartbeat extends ConsumerStatefulWidget {
  const ActivityHeartbeat({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ActivityHeartbeat> createState() => _ActivityHeartbeatState();
}

class _ActivityHeartbeatState extends ConsumerState<ActivityHeartbeat>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Tras el primer fotograma y no dentro de `initState`: latir aquí dispararía una escritura
    // mientras el árbol se está montando, y un fallo de red en ese instante llega antes de que haya
    // nada donde enseñarlo.
    WidgetsBinding.instance.addPostFrameCallback((_) => _latir());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Solo `resumed`. `inactive` y `paused` llegan también al bajar la persiana de notificaciones o
    // al girar el móvil, y latir ahí sería el temporizador corto por la puerta de atrás.
    if (state == AppLifecycleState.resumed) _latir();
  }

  Future<void> _latir() async {
    try {
      await ref.read(activityRepositoryProvider).heartbeat();
    } on Object {
      // Ver la nota de la clase: un latido perdido apaga un punto antes de tiempo, nada más.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
