# -*- coding: utf-8 -*-
"""Genera los 8 avatares de Grasp como SVG a partir de una base comun.

La base (cuerpo, ojos, boca, pies, destellos) es identica en los ocho: eso es lo que hace que
parezcan una familia y no ocho dibujos sueltos. Lo que cambia por avatar es el color del cuerpo,
el del fondo, el accesorio y la expresion.

El color pesa mas que el accesorio: a 96 px el detalle del accesorio se empasta, y lo unico que
distingue un avatar de otro de un vistazo es la pareja cuerpo/fondo. Por eso ninguna se repite.
"""
import io
import os

OUT = os.path.dirname(os.path.abspath(__file__))

INK = "#101010"          # contorno, comun a todo
SPARK = "#FFFFFF"        # destellos, con opacidad

# ---------------------------------------------------------------- piezas comunes

def sparkles(color, op=0.55):
    def s(cx, cy, r):
        return (f'<path d="M{cx} {cy-r} l{r*0.3:.0f} {r*0.7:.0f} {r*0.7:.0f} {r*0.3:.0f} '
                f'-{r*0.7:.0f} {r*0.3:.0f} -{r*0.3:.0f} {r*0.7:.0f} '
                f'-{r*0.3:.0f} -{r*0.7:.0f} -{r*0.7:.0f} -{r*0.3:.0f} '
                f'{r*0.7:.0f} -{r*0.3:.0f}z" fill="{color}" opacity="{op}"/>')
    return s(86, 132, 34) + s(436, 176, 26) + s(410, 396, 20)

def body(fill, highlight):
    return f'''
      <path d="M256 92 c 80 0 126 54 126 126 c 0 72 -48 126 -126 126
               c -78 0 -126 -54 -126 -126 c 0 -72 46 -126 126 -126 z" fill="{fill}"/>
      <path d="M170 176 c 10 -36 38 -60 68 -64" fill="none" stroke="{highlight}" stroke-width="15"/>'''

def legs(foot):
    return f'''
      <path d="M212 372 v46" fill="none"/>
      <path d="M300 372 v46" fill="none"/>
      <ellipse cx="204" cy="428" rx="30" ry="15" fill="{foot}"/>
      <ellipse cx="308" cy="428" rx="30" ry="15" fill="{foot}"/>'''

def eyes(kind="open"):
    if kind == "wink":
        return '''
      <circle cx="212" cy="192" r="33" fill="#FFFFFF"/>
      <circle cx="216" cy="196" r="13" fill="#101010" stroke="none"/>
      <path d="M282 196 q 20 -18 40 0" fill="none"/>'''
    if kind == "happy":   # dos arcos, ojos de sonrisa
        return '''
      <path d="M190 200 q 22 -30 44 0" fill="none"/>
      <path d="M280 200 q 22 -30 44 0" fill="none"/>'''
    return '''
      <circle cx="212" cy="192" r="33" fill="#FFFFFF"/>
      <circle cx="302" cy="192" r="33" fill="#FFFFFF"/>
      <circle cx="216" cy="196" r="13" fill="#101010" stroke="none"/>
      <circle cx="306" cy="196" r="13" fill="#101010" stroke="none"/>'''

def mouth(kind="smile"):
    if kind == "open":
        return ('<path d="M226 246 q 30 8 60 0 q -6 40 -30 40 q -24 0 -30 -40z" fill="#3A1B4A"/>'
                '<path d="M242 282 q 14 12 28 0" fill="#FF7BA8" stroke="none"/>')
    if kind == "grin":
        return '<path d="M220 248 q 36 40 72 0" fill="none"/>'
    return '<path d="M224 250 q 32 34 64 0" fill="none"/>'

def arms_down(fill):
    """Brazos hacia delante, para sujetar un accesorio."""
    return f'''
      <path d="M150 258 q -26 50 28 68" fill="none" stroke-width="30"/>
      <path d="M362 258 q 26 50 -28 68" fill="none" stroke-width="30"/>
      <path d="M150 258 q -26 50 28 68" fill="none" stroke="{fill}" stroke-width="16"/>
      <path d="M362 258 q 26 50 -28 68" fill="none" stroke="{fill}" stroke-width="16"/>'''

def arms_wave(fill):
    """Uno saluda arriba, otro cae: para los avatares sin accesorio."""
    return f'''
      <path d="M146 250 q -46 -18 -54 -64" fill="none" stroke-width="30"/>
      <path d="M366 262 q 34 30 22 74" fill="none" stroke-width="30"/>
      <path d="M146 250 q -46 -18 -54 -64" fill="none" stroke="{fill}" stroke-width="16"/>
      <path d="M366 262 q 34 30 22 74" fill="none" stroke="{fill}" stroke-width="16"/>
      <circle cx="92" cy="186" r="17" fill="{fill}"/>
      <circle cx="388" cy="336" r="17" fill="{fill}"/>'''

# ---------------------------------------------------------------- accesorios

ACC = {}

ACC["coding"] = '''
      <rect x="184" y="300" width="144" height="74" rx="10" fill="#12324F"/>
      <path d="M168 374 h176 l20 28 h-216 z" fill="#2BD9A6"/>
      <path d="M214 322 l-15 15 15 15" fill="none" stroke="#2BD9A6" stroke-width="8"/>
      <path d="M298 322 l15 15 -15 15" fill="none" stroke="#2BD9A6" stroke-width="8"/>
      <path d="M244 352 l24 -30" fill="none" stroke="#FFD54A" stroke-width="8"/>'''

ACC["gym"] = '''
      <path d="M176 330 h160" fill="none" stroke-width="16"/>
      <rect x="120" y="286" width="58" height="88" rx="16" fill="#FF6B6B"/>
      <rect x="334" y="286" width="58" height="88" rx="16" fill="#FF6B6B"/>
      <rect x="88" y="306" width="34" height="48" rx="11" fill="#FFD54A"/>
      <rect x="390" y="306" width="34" height="48" rx="11" fill="#FFD54A"/>'''

ACC["reader"] = '''
      <path d="M256 306 q -46 -22 -84 -8 v78 q 40 -14 84 6z" fill="#FF9F45"/>
      <path d="M256 306 q 46 -22 84 -8 v78 q -40 -14 -84 6z" fill="#FFC078"/>
      <path d="M256 306 v76" fill="none" stroke-width="8"/>
      <path d="M196 336 h40 M196 358 h40" fill="none" stroke-width="6"/>
      <path d="M276 336 h40 M276 358 h40" fill="none" stroke-width="6"/>'''

ACC["music"] = '''
      <path d="M150 196 a 106 106 0 0 1 212 0" fill="none" stroke-width="16"/>
      <rect x="118" y="186" width="52" height="76" rx="24" fill="#FF6B6B"/>
      <rect x="342" y="186" width="52" height="76" rx="24" fill="#FF6B6B"/>
      <circle cx="330" cy="352" r="20" fill="#FFD54A"/>
      <path d="M348 352 v-56 l34 -10 v56" fill="none" stroke-width="9"/>
      <circle cx="368" cy="342" r="18" fill="#FFD54A"/>'''

ACC["animal"] = '''
      <path d="M244 236 h24 l-12 14z" fill="#FF9BB3"/>'''

# Orejas de gato: van DETRAS del cuerpo, asi que se inyectan aparte.
EARS = '''
      <path d="M158 148 l6 -78 66 44z" fill="{fill}"/>
      <path d="M354 148 l-6 -78 -66 44z" fill="{fill}"/>
      <path d="M176 136 l4 -44 36 24z" fill="#FF9BB3" stroke="none"/>
      <path d="M336 136 l-4 -44 -36 24z" fill="#FF9BB3" stroke="none"/>'''

ACC["normal_1"] = ''
ACC["normal_2"] = ''
ACC["normal_3"] = '''
      <path d="M158 186 h196" fill="none" stroke-width="10"/>
      <path d="M164 176 h64 a10 10 0 0 1 10 10 v14 a30 30 0 0 1 -60 0 v-14 a10 10 0 0 1 -14 -10z" fill="#12324F" opacity="0.92"/>
      <path d="M284 176 h64 a10 10 0 0 1 10 10 v14 a30 30 0 0 1 -60 0 v-14 a10 10 0 0 1 -14 -10z" fill="#12324F" opacity="0.92"/>'''

# ---------------------------------------------------------------- los ocho

# (fichero, cuerpo, brillo, fondo, pie, ojos, boca, brazos, accesorio, orejas)
AVATARS = [
    ("coding-user",   "#8B5CF6", "#C4B5FD", "#5B4BE8", "#FFD54A", "open",  "smile", "down", "coding",   False),
    ("gym-user",      "#2BD9A6", "#9DF5DC", "#0E7C6B", "#FFD54A", "happy", "grin",  "down", "gym",      False),
    ("reader-user",   "#FFD54A", "#FFEDA6", "#2A6F97", "#FF6B6B", "open",  "smile", "down", "reader",   False),
    ("music-user",    "#FF7BA8", "#FFC2D6", "#6D28D9", "#2BD9A6", "happy", "open",  "down", "music",    False),
    ("animal-user",   "#FF9F45", "#FFD3A6", "#2BA84A", "#FFFFFF", "open",  "smile", "wave", "animal",   True),
    ("normal-user-1", "#4EA8FF", "#B3DBFF", "#F26B5E", "#FFD54A", "open",  "smile", "wave", "normal_1", False),
    ("normal-user-2", "#FF6B6B", "#FFB8B8", "#2A6F97", "#FFD54A", "wink",  "grin",  "wave", "normal_2", False),
    ("normal-user-3", "#9DE04F", "#D6F5AE", "#4C1D95", "#FF7BA8", "open",  "smile", "wave", "normal_3", False),
]


def build(name, fill, hi, bg, foot, eye, mou, arm, acc, ears):
    ear_svg = EARS.format(fill=fill) if ears else ""
    arms = arms_down(fill) if arm == "down" else arms_wave(fill)
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">
  <defs><clipPath id="f"><rect width="512" height="512" rx="96"/></clipPath></defs>
  <g clip-path="url(#f)">
    <rect width="512" height="512" fill="{bg}"/>
    {sparkles(SPARK)}
    <g stroke="{INK}" stroke-width="9" stroke-linejoin="round" stroke-linecap="round">
      {ear_svg}{legs(foot)}{body(fill, hi)}{eyes(eye)}
      {mouth(mou)}{arms}{ACC[acc]}
    </g>
  </g>
</svg>
'''


if __name__ == "__main__":
    for row in AVATARS:
        svg = build(*row)
        io.open(os.path.join(OUT, row[0] + ".svg"), "w", encoding="utf-8").write(svg)
        print("escrito", row[0] + ".svg")
