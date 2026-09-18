import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { LISTENER_PROFILES, listenerProfileName } from "./onboarding-catalogs.ts";

// =================================================================================================
// El nombre del perfil de oyente — la señal no sensible que pinta la tarjeta de Conectar
// =================================================================================================

Deno.test("listenerProfileName: traduce el slug al nombre que se ensena", () => {
  // `onboarding_responses.responses.profile` guarda el SLUG: el cliente manda `slug` al completar
  // el onboarding, no `name`. `connect-feed` lo devolvia crudo y la tarjeta pintaba
  // «empatico-cercano» tal cual, que es un identificador interno, no una senal.
  // Se vio en el emulador, no en un test.
  assertEquals(listenerProfileName("empatico-cercano"), "Empático y cercano");
  assertEquals(listenerProfileName("directo-practico"), "Directo y práctico");
});

Deno.test("listenerProfileName: todos los slugs del catalogo se resuelven", () => {
  for (const option of LISTENER_PROFILES) {
    assertEquals(listenerProfileName(option.slug), option.name, option.slug);
  }
});

Deno.test("listenerProfileName: un slug desconocido da null, NO el slug", () => {
  // Devolver el slug como respaldo seria peor que no pintar nada: acabaria en la pantalla de
  // alguien. Ante un valor que este catalogo no conoce, la tarjeta se queda sin ese chip.
  for (const basura of ["no-existe", "", "Empático y cercano", null, undefined]) {
    assertEquals(listenerProfileName(basura), null, `${basura}`);
  }
});

Deno.test("listenerProfileName: ningun nombre del catalogo parece un slug", () => {
  // Si alguien anade una opcion con `name` en kebab-case, la tarjeta volveria a ensenar algo que
  // parece un identificador aunque la traduccion funcione.
  for (const option of LISTENER_PROFILES) {
    assertEquals(
      /^[a-z0-9-]+$/.test(option.name),
      false,
      `el nombre de ${option.slug} parece un slug: ${option.name}`,
    );
  }
});
