#!/usr/bin/env python3
"""Gera os PNGs do icone do Etiquetas CAMDA (sem arquivo-base: o glifo e desenhado aqui).

Glifo: uma etiqueta branca inclinada, com furo e duas barras (nome grande + codigo) vazadas.
  etiqueta_fg.png      adaptativo, primeiro plano (branco, dentro da zona segura de 66 dp numa tela de 108 dp);
                       tambem serve de icone tematico (monocromatico) do Android 13+
  etiqueta_bg.png      adaptativo, fundo: gradiente azul-petroleo, claro embaixo a esquerda
  etiqueta_legacy.png  icone normal (Android antigo): quadrado arredondado com o glifo

Rodar: python3 tool/gerar_icone.py   (precisa de Pillow). Os PNGs ficam no repositorio;
o CI so roda o flutter_launcher_icons.
"""
from pathlib import Path

from PIL import Image, ImageDraw

PASTA = Path(__file__).resolve().parent.parent / "assets" / "icon"
TAM = 1024
SS = 2  # supersampling
PARADAS = [(0.0, (27, 163, 163)), (0.55, (20, 110, 150)), (1.0, (14, 62, 112))]


def gradiente(tam):
    img = Image.new("RGB", (tam, tam))
    px = img.load()
    for y in range(tam):
        for x in range(tam):
            # 0 = canto inferior esquerdo, 1 = superior direito
            t = ((x / (tam - 1)) + (1 - y / (tam - 1))) / 2
            for (t0, c0), (t1, c1) in zip(PARADAS, PARADAS[1:]):
                if t <= t1:
                    k = (t - t0) / (t1 - t0)
                    px[x, y] = tuple(round(a + (b - a) * k) for a, b in zip(c0, c1))
                    break
    return img


def glifo(tam, escala=1.0):
    """Mascara L (255 = branco) da etiqueta com furo e barras vazadas, ja inclinada."""
    n = tam * SS
    c = n / 2
    m = Image.new("L", (n, n), 0)
    d = ImageDraw.Draw(m)
    w, h = 500 * SS * escala * tam / TAM, 350 * SS * escala * tam / TAM
    x0, y0, x1, y1 = c - w / 2, c - h / 2, c + w / 2, c + h / 2
    d.rounded_rectangle((x0, y0, x1, y1), radius=h * 0.14, fill=255)
    # furo da etiqueta
    r = h * 0.075
    d.ellipse((x0 + h * 0.17 - r, c - r, x0 + h * 0.17 + r, c + r), fill=0)
    # barras vazadas: nome (grossa) e codigo (fina)
    bx0, bx1 = x0 + h * 0.40, x1 - h * 0.17
    d.rounded_rectangle((bx0, c - h * 0.20, bx1, c - h * 0.04), radius=h * 0.05, fill=0)
    d.rounded_rectangle((bx0, c + h * 0.10, bx0 + (bx1 - bx0) * 0.68, c + h * 0.20), radius=h * 0.04, fill=0)
    m = m.rotate(12, resample=Image.BICUBIC, center=(c, c))
    return m.resize((tam, tam), Image.LANCZOS)


def main():
    PASTA.mkdir(parents=True, exist_ok=True)
    # primeiro plano: branco com a mascara como alfa
    fg = Image.new("RGBA", (TAM, TAM), (255, 255, 255, 0))
    fg.putalpha(glifo(TAM))
    fg.save(PASTA / "etiqueta_fg.png")
    # fundo
    bg = gradiente(TAM)
    bg.save(PASTA / "etiqueta_bg.png")
    # legado: quadrado arredondado + glifo um pouco maior
    leg = Image.new("RGBA", (TAM, TAM), (0, 0, 0, 0))
    base = bg.convert("RGBA")
    mask = Image.new("L", (TAM * SS, TAM * SS), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, TAM * SS - 1, TAM * SS - 1), radius=int(TAM * SS * 0.22), fill=255)
    leg.paste(base, (0, 0), mask.resize((TAM, TAM), Image.LANCZOS))
    g = Image.new("RGBA", (TAM, TAM), (255, 255, 255, 0))
    g.putalpha(glifo(TAM, 1.18))
    leg.alpha_composite(g)
    leg.save(PASTA / "etiqueta_legacy.png")


if __name__ == "__main__":
    main()
