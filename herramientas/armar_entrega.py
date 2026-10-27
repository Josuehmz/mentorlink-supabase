#!/usr/bin/env python3
"""Mantiene la documentación sin divergir de los archivos fuente.

    python herramientas/armar_entrega.py              # sincroniza docs/ y escribe ENTREGA.md
    python herramientas/armar_entrega.py --verificar  # no escribe nada; sale con 1 si algo difiere

Hace tres cosas:
1. En docs/*.md, reemplaza cada bloque <!-- INCLUIR: ruta --> ... <!-- /INCLUIR --> por el
   contenido exacto de esa ruta (la migración SQL, los prompts). Así el documento nunca diverge
   de la fuente de verdad.
2. Arma ENTREGA.md (documento único del enunciado) con una portada y docs/01..05, ajustando
   los enlaces relativos para que funcionen desde la raíz.
3. Comprueba que todos los enlaces relativos de README.md, ENTREGA.md y docs/*.md apuntan a
   archivos que existen y, si llevan ancla (#...), a un encabezado que existe.
"""
from __future__ import annotations

import posixpath
import re
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
DOCS = sorted((RAIZ / "docs").glob("0[1-9]-*.md"))
ENTREGA = RAIZ / "ENTREGA.md"
REPO_URL = "https://github.com/Josuehmz/mentorlink-supabase"

BLOQUE = re.compile(r"<!-- INCLUIR: (?P<ruta>\S+) -->\n.*?<!-- /INCLUIR -->", re.S)
ENLACE = re.compile(r"(?<!!)\[(?P<texto>[^\]]*)\]\((?P<destino>[^)\s]+)\)")
LENGUAJE = {".sql": "sql", ".txt": "text", ".sh": "bash", ".toml": "toml"}

PORTADA = f"""# MentorLink: infraestructura con Supabase e IA

Proyecto Integrador: Implementación de Infraestructura con Supabase e IA.

| Campo | Valor |
|---|---|
| Materia | [Materia] |
| Integrantes | [Integrantes] |
| Fecha de entrega | 29 de octubre de 2026 |
| Repositorio | {REPO_URL} |

Este documento reúne los cuatro entregables del enunciado, en orden, más la auditoría:

| Entregable del enunciado | Sección |
|---|---|
| Scripts SQL generados (tablas y políticas RLS completas) | [1. Esquema de datos y políticas RLS](#1-esquema-de-datos-y-políticas-rls) |
| Prompt de IA utilizado (texto exacto) | [2. Prompts de IA utilizados](#2-prompts-de-ia-utilizados) |
| Capturas o log de comandos de la CLI | [3. Supabase CLI: comandos y evidencia](#3-supabase-cli-comandos-y-evidencia) |
| Guía de configuración Auth (3 pasos para Google) | [4. Guía de configuración de Auth](#4-guía-de-configuración-de-auth-emailpassword-y-google) |
| Auditoría IA (cuatro ejes) | [5. Auditoría IA](#5-auditoría-ia-los-cuatro-ejes) |

Qué se ejecutó y qué no: la CLI de Supabase 2.122.0 se ejecutó en local (`init`, `migration new`,
`start`, `db reset`, `migration list --local`, `test db`, `stop`); `supabase test db` pasó las 41
pruebas pgTAP y la salida de cada comando está en `docs/evidencia/cli/`. Los pasos de la nube
(`login`, `link`, `db push`) no se ejecutaron porque no existe un proyecto en la nube;
`<project-ref>` y las credenciales de Google son marcadores.

"""


def leer(ruta: Path) -> str:
    return ruta.read_text(encoding="utf-8").replace("\r\n", "\n")


def slug(titulo: str) -> str:
    """Ancla de GitHub para un encabezado."""
    titulo = re.sub(r"[`*_]", "", titulo.strip().lower())
    titulo = re.sub(r"[^\w\- ]", "", titulo)
    return titulo.replace(" ", "-")


def fuera_de_codigo(texto: str):
    """Itera (es_codigo, linea) respetando bloques ``` y ````."""
    cerca = None
    for linea in texto.split("\n"):
        m = re.match(r"^(`{3,})", linea)
        if m:
            if cerca is None:
                cerca = m.group(1)
                yield True, linea
                continue
            if linea.strip() == cerca:
                cerca = None
                yield True, linea
                continue
        yield cerca is not None, linea


def anclas(texto: str) -> set[str]:
    vistas: dict[str, int] = {}
    resultado = set()
    for es_codigo, linea in fuera_de_codigo(texto):
        m = re.match(r"^#{1,6} (.+)$", linea)
        if es_codigo or not m:
            continue
        base = slug(m.group(1))
        n = vistas.get(base, 0)
        resultado.add(base if n == 0 else f"{base}-{n}")
        vistas[base] = n + 1
    return resultado


def sincronizar(texto: str, carpeta: Path) -> str:
    def reemplazo(m: re.Match) -> str:
        ruta = m.group("ruta")
        fuente = (carpeta / ruta).resolve()
        contenido = leer(fuente)
        if not contenido.endswith("\n"):
            contenido += "\n"
        lenguaje = LENGUAJE.get(fuente.suffix, "")
        return f"<!-- INCLUIR: {ruta} -->\n````{lenguaje}\n{contenido}````\n<!-- /INCLUIR -->"

    return BLOQUE.sub(reemplazo, texto)


def titulo_de(doc: Path) -> str:
    for linea in leer(doc).split("\n"):
        if linea.startswith("# "):
            return linea[2:]
    raise SystemExit(f"{doc} no tiene título")


def armar_entrega(textos: dict[Path, str]) -> str:
    partes = [PORTADA]
    docs_por_ruta = {posixpath.join("docs", d.name): d for d in DOCS}
    for doc in DOCS:
        lineas = []
        for es_codigo, linea in fuera_de_codigo(textos[doc]):
            if not es_codigo and re.match(r"^<!-- /?INCLUIR", linea):
                continue  # los marcadores solo sirven en docs/; en la entrega saldrían como texto
            if not es_codigo:
                if re.match(r"^#{1,5} ", linea):
                    linea = "#" + linea

                def ajustar(m: re.Match) -> str:
                    destino = m.group("destino")
                    if re.match(r"^(https?:|mailto:|#)", destino):
                        return m.group(0)
                    ruta, _, ancla = destino.partition("#")
                    resuelta = posixpath.normpath(posixpath.join("docs", ruta))
                    if resuelta in docs_por_ruta:
                        nuevo = "#" + (ancla or slug(titulo_de(docs_por_ruta[resuelta])))
                    else:
                        nuevo = resuelta + ("/" if ruta.endswith("/") else "") + (f"#{ancla}" if ancla else "")
                    return f"[{m.group('texto')}]({nuevo})"

                linea = ENLACE.sub(ajustar, linea)
            lineas.append(linea)
        partes.append("\n".join(lineas).rstrip("\n") + "\n\n")
    return "".join(partes).rstrip("\n") + "\n"


def comprobar_enlaces(archivo: Path, texto: str) -> list[str]:
    errores = []
    for es_codigo, linea in fuera_de_codigo(texto):
        if es_codigo:
            continue
        for m in ENLACE.finditer(linea):
            destino = m.group("destino")
            if re.match(r"^(https?:|mailto:)", destino):
                continue
            ruta, _, ancla = destino.partition("#")
            objetivo = (archivo.parent / ruta).resolve() if ruta else archivo
            if not objetivo.exists():
                errores.append(f"{archivo.relative_to(RAIZ)}: no existe {destino}")
                continue
            if ancla and objetivo.suffix == ".md" and ancla not in anclas(leer(objetivo)):
                errores.append(f"{archivo.relative_to(RAIZ)}: no existe el ancla {destino}")
    return errores


def main() -> int:
    verificar = "--verificar" in sys.argv
    desactualizados = []
    textos = {}
    for doc in DOCS:
        original = leer(doc)
        nuevo = sincronizar(original, doc.parent)
        textos[doc] = nuevo
        if nuevo != original:
            desactualizados.append(doc.relative_to(RAIZ).as_posix())
            if not verificar:
                doc.write_text(nuevo, encoding="utf-8", newline="\n")
    entrega = armar_entrega(textos)
    if not ENTREGA.exists() or leer(ENTREGA) != entrega:
        desactualizados.append("ENTREGA.md")
        if not verificar:
            ENTREGA.write_text(entrega, encoding="utf-8", newline="\n")

    errores = []
    for archivo in [RAIZ / "README.md", ENTREGA, *DOCS]:
        if archivo.exists():
            errores += comprobar_enlaces(archivo, leer(archivo))

    if verificar and desactualizados:
        errores += [f"desactualizado respecto a su fuente: {d}" for d in desactualizados]
    elif desactualizados:
        print("Actualizados:", ", ".join(desactualizados))
    for e in errores:
        print("ERROR", e)
    if not errores:
        print("OK: documentos sincronizados con sus fuentes y enlaces relativos válidos")
    return 1 if errores else 0


if __name__ == "__main__":
    raise SystemExit(main())
