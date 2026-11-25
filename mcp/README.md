# patchdeck-mcp

Servidor [MCP](https://modelcontextprotocol.io) para que Claude (Claude Code, Claude Desktop o cualquier cliente MCP)
maneje Patchdeck: leer reviews y patches, dejar comentarios anclados a líneas con etiquetas, editar contexto y
notas, marcar archivos como vistos y administrar las etiquetas.

Trabaja directamente sobre los archivos de Patchdeck (los mismos que usa la app, ver *Dónde se guardan los datos*
en el README principal). **La app no necesita estar abierta**; si lo está, recarga sola lo que escribe el servidor:
los comentarios nuevos aparecen en el diff, las etiquetas en Configuración y los cambios que tengas sin guardar se
conservan.

## Instalación

Requiere Node.js ≥ 20.

```bash
cd mcp
npm install
npm run build
```

### Claude Code

```bash
claude mcp add --scope user patchdeck -- node "$PWD/dist/src/index.js"
```

(ejecutado desde `mcp/`; `--scope user` lo deja disponible en todos tus proyectos).

### Claude Desktop

En `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "patchdeck": {
      "command": "node",
      "args": ["/ruta/a/patchdeck/mcp/dist/src/index.js"]
    }
  }
}
```

### Otra ubicación de datos

Por defecto usa las mismas rutas que la app (XDG en Linux, `%APPDATA%\Patchdeck` en Windows). Para otra carpeta:
`PATCHDECK_CONFIG_DIR` (donde está `settings.json`) y `PATCHDECK_DATA_DIR` (donde está `reviews/`).

## Herramientas

| Herramienta | Qué hace |
|---|---|
| `list_reviews` | Reviews, la más reciente primero |
| `get_review` | Contexto, notas, patches con sus archivos (`+/−`, visto, comentarios) y todos los comentarios |
| `get_patch` | Código de un patch (o de un archivo) con números de línea viejo/nuevo explícitos y marcas de lo ya comentado |
| `create_review` / `update_review` | Crear una review; cambiar título, contexto o notas (reemplazar o `append`) |
| `add_patch` | Agregar un patch pegando el texto o con la ruta de un `.patch`/`.diff` local |
| `rename_patch` | Renombrar la pestaña de un patch |
| `set_file_viewed` | Marcar / desmarcar un archivo como visto |
| `list_comments` | Comentarios filtrados por patch, archivo o etiqueta |
| `add_comment` | Comentario sobre líneas, rangos o archivos completos, en uno o varios archivos/patches, con etiquetas |
| `update_comment` | Editar texto, etiquetas (`labels`, `add_labels`, `remove_labels`), ubicación o *denegar* |
| `delete_comment` | Eliminar un comentario |
| `export_review` | La review en Markdown ("Copiar review") o los comentarios con tu plantilla ("Copiar todos") |
| `list_labels` | Etiquetas en el orden de la app; con `include_usage` cuenta cuántos comentarios usan cada una |
| `create_label` / `update_label` | Crear o editar etiquetas (título, descripción, color `#RRGGBB`) |
| `delete_label` | Eliminar una etiqueta; con `remove_from_comments` también se quita de los comentarios |
| `reorder_labels` | Cambiar el orden de las etiquetas |

Las reviews se pueden nombrar por id o por título, los patches por su nombre (`A`, `B`, …) y las etiquetas por
título o id. Si una línea no está en el patch, el error dice qué rangos son válidos.

No hay herramientas para borrar reviews ni patches; eso queda en la app.

### Ejemplos de pedidos

- *"Revisa la review «PR 128»: lee los patches y deja comentarios con las etiquetas bug, nit o pregunta."*
- *"Crea una review con `git diff main...` de este repo y comenta los problemas de seguridad."* (Claude guarda el
  diff en un archivo y usa `add_patch` con `file_path`.)
- *"Crea una etiqueta «refactor» verde y pásale los comentarios de nit que hablen de estructura."*
- *"Exporta la review en Markdown."*

## Cómo convive con la app

- Cada cambio es una lectura-modificación-escritura **atómica** de un solo archivo (temporal + `rename`), igual
  que la app. Los campos que el servidor no conoce se conservan.
- La app vigila `reviews/` y `settings.json`. Distingue sus propias escrituras de las ajenas por fecha de
  modificación y tamaño, y fusiona en tres vías contra la última versión que leyó: lo que sólo cambió un lado se
  toma tal cual; si los dos editaron el mismo comentario gana el más reciente. Antes de cada guardado vuelve a
  comprobar el disco, así nunca pisa un cambio que el watcher todavía no informó.

## Desarrollo

```bash
npm test   # compila y corre los tests (node:test), incluido uno de punta a punta por stdio
```

`src/diff.ts` y `src/format.ts` son ports de `lib/diff/diff_parser.dart` y `lib/state/comment_format.dart` /
`review_export.dart`: si cambia la numeración de líneas o el formato de copiado en la app, hay que actualizarlos.
