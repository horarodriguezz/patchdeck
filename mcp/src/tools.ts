import type { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { z } from 'zod';

import type { Patchdeck } from './ops.js';
import { UserError } from './store.js';

const review = z.string().describe('Id de la review o su título (también vale un fragmento único del título).');
const patch = z.string().describe('Nombre del patch (A, B, …) o su id. Opcional si la review tiene un solo patch.');
const labelRefs = z.array(z.string()).describe('Etiquetas por título (p. ej. "bug", "nit") o id.');

const location = z.object({
  patch: patch.optional(),
  path: z.string().describe('Ruta del archivo tal como aparece en el patch (p. ej. src/app.ts).'),
  line: z
    .number()
    .int()
    .positive()
    .optional()
    .describe('Línea a comentar. Omítela para comentar el archivo completo.'),
  end_line: z.number().int().positive().optional().describe('Última línea de un rango (inclusive).'),
  side: z
    .enum(['new', 'old'])
    .optional()
    .describe('Numeración de "line": "new" (por defecto, archivo nuevo) u "old" (para líneas eliminadas).'),
});

type Handler<A> = (args: A) => Promise<unknown>;

function wrap<A>(fn: Handler<A>) {
  return async (args: A) => {
    try {
      const out = await fn(args);
      const text = typeof out === 'string' ? out : JSON.stringify(out, null, 2);
      return { content: [{ type: 'text' as const, text }] };
    } catch (e) {
      const msg = e instanceof UserError ? e.message : `Error interno: ${(e as Error).stack ?? String(e)}`;
      return { content: [{ type: 'text' as const, text: msg }], isError: true };
    }
  };
}

const readOnly = { readOnlyHint: true, destructiveHint: false, openWorldHint: false } as const;
const write = { readOnlyHint: false, destructiveHint: false, openWorldHint: false } as const;
const destructive = { readOnlyHint: false, destructiveHint: true, openWorldHint: false } as const;

export function registerTools(server: McpServer, pd: Patchdeck): void {
  // ------------------------------------------------------------- reviews

  server.registerTool(
    'list_reviews',
    {
      title: 'Listar reviews',
      description: 'Reviews guardadas en Patchdeck, la más reciente primero (id, título, patches y cantidad de comentarios).',
      inputSchema: {},
      annotations: readOnly,
    },
    wrap(() => pd.listReviews()),
  );

  server.registerTool(
    'get_review',
    {
      title: 'Ver review',
      description:
        'Detalle de una review: contexto y notas (Markdown), patches con su lista de archivos (+/-, visto, comentarios) ' +
        'y todos los comentarios con etiquetas y ubicación. No incluye el código: usa get_patch.',
      inputSchema: { review },
      annotations: readOnly,
    },
    wrap((a) => pd.getReview(a.review)),
  );

  server.registerTool(
    'get_patch',
    {
      title: 'Leer patch',
      description:
        'Código de un patch con números de línea viejo/nuevo explícitos por fila (los que espera add_comment). ' +
        'Las líneas ya comentadas se marcan con "◀ comentado". Filtra con "file" en patches grandes.',
      inputSchema: {
        review,
        patch: patch.optional(),
        file: z.string().optional().describe('Sólo este archivo.'),
        format: z
          .enum(['annotated', 'raw'])
          .optional()
          .describe('"annotated" (por defecto) con números de línea, o "raw": el diff tal cual se pegó.'),
        max_lines: z.number().int().positive().optional().describe('Corta la salida (por defecto 3000 líneas).'),
      },
      annotations: readOnly,
    },
    wrap((a) => pd.getPatch(a)),
  );

  server.registerTool(
    'create_review',
    {
      title: 'Crear review',
      description: 'Crea una review vacía. Después agrega patches con add_patch.',
      inputSchema: {
        title: z.string(),
        context: z.string().optional().describe('Markdown para la pestaña Contexto (p. ej. la descripción del PR).'),
        notes: z.string().optional().describe('Markdown para el panel Notas.'),
      },
      annotations: write,
    },
    wrap((a) => pd.createReview(a)),
  );

  server.registerTool(
    'update_review',
    {
      title: 'Editar review',
      description: 'Cambia el título, el contexto o las notas (Markdown). Con append=true el texto se agrega al final.',
      inputSchema: {
        review,
        title: z.string().optional(),
        context: z.string().optional(),
        notes: z.string().optional(),
        append: z.boolean().optional().describe('Agrega contexto/notas al final en vez de reemplazarlos.'),
      },
      annotations: write,
    },
    wrap((a) => pd.updateReview(a)),
  );

  server.registerTool(
    'add_patch',
    {
      title: 'Agregar patch',
      description:
        'Agrega un patch (git diff, git show, git format-patch o diff -u) a la review. Pasa el texto en "diff" ' +
        'o la ruta de un archivo .patch/.diff local en "file_path" (mejor para diffs grandes).',
      inputSchema: {
        review,
        diff: z.string().optional(),
        file_path: z.string().optional(),
        name: z.string().optional().describe('Nombre de la pestaña; por defecto la siguiente letra libre (A, B, …).'),
      },
      annotations: write,
    },
    wrap((a) => pd.addPatch(a)),
  );

  server.registerTool(
    'rename_patch',
    {
      title: 'Renombrar patch',
      description: 'Cambia el nombre de la pestaña de un patch.',
      inputSchema: { review, patch, name: z.string() },
      annotations: write,
    },
    wrap((a) => pd.renamePatch(a)),
  );

  server.registerTool(
    'set_file_viewed',
    {
      title: 'Marcar archivo como visto',
      description: 'Marca o desmarca un archivo de un patch como "visto" (como el checkbox del encabezado).',
      inputSchema: { review, patch: patch.optional(), path: z.string(), viewed: z.boolean() },
      annotations: write,
    },
    wrap((a) => pd.setFileViewed(a)),
  );

  // ------------------------------------------------------------ comments

  server.registerTool(
    'list_comments',
    {
      title: 'Listar comentarios',
      description: 'Comentarios de una review, con filtros opcionales por patch, archivo y etiqueta.',
      inputSchema: {
        review,
        patch: patch.optional(),
        path: z.string().optional(),
        label: z.string().optional().describe('Título o id de etiqueta.'),
        include_dismissed: z.boolean().optional().describe('Incluir denegados (por defecto sí).'),
      },
      annotations: readOnly,
    },
    wrap((a) => pd.listComments(a)),
  );

  server.registerTool(
    'add_comment',
    {
      title: 'Agregar comentario',
      description:
        'Agrega un comentario anclado a líneas, rangos o archivos completos (puede combinar varios archivos y patches, ' +
        'como la selección con Ctrl+clic). Los números de línea son los de get_patch; si una línea no está en el ' +
        'patch, el error dice qué rangos son válidos. Las etiquetas deben existir (ver list_labels / create_label).',
      inputSchema: {
        review,
        text: z.string().describe('Texto del comentario (Markdown).'),
        locations: z.array(location).min(1),
        labels: labelRefs.optional(),
      },
      annotations: write,
    },
    wrap((a) => pd.addComment(a)),
  );

  server.registerTool(
    'update_comment',
    {
      title: 'Editar comentario',
      description:
        'Edita texto, etiquetas (reemplazar con "labels" o ajustar con add_labels / remove_labels), ubicación o ' +
        'estado denegado de un comentario.',
      inputSchema: {
        review,
        comment_id: z.string(),
        text: z.string().optional(),
        labels: labelRefs.optional().describe('Reemplaza todas las etiquetas.'),
        add_labels: labelRefs.optional(),
        remove_labels: labelRefs.optional(),
        dismissed: z.boolean().optional().describe('true = denegado (se conserva pero no se copia).'),
        locations: z.array(location).min(1).optional().describe('Reemplaza la ubicación.'),
      },
      annotations: write,
    },
    wrap((a) => pd.updateComment(a)),
  );

  server.registerTool(
    'delete_comment',
    {
      title: 'Eliminar comentario',
      description: 'Elimina un comentario. Para descartarlo sin perderlo usa update_comment con dismissed=true.',
      inputSchema: { review, comment_id: z.string() },
      annotations: destructive,
    },
    wrap((a) => pd.deleteComment(a)),
  );

  server.registerTool(
    'export_review',
    {
      title: 'Exportar review',
      description:
        '"markdown": la review completa (contexto, comentarios por patch, notas) como "Copiar review". ' +
        '"comments": los comentarios activos con la plantilla de copiado de Configuración, como "Copiar todos".',
      inputSchema: { review, format: z.enum(['markdown', 'comments']).optional() },
      annotations: readOnly,
    },
    wrap((a) => pd.exportReview(a)),
  );

  // -------------------------------------------------------------- labels

  server.registerTool(
    'list_labels',
    {
      title: 'Listar etiquetas',
      description: 'Etiquetas configuradas (id, título, descripción, color #AARRGGBB), en el orden de la app.',
      inputSchema: {
        include_usage: z.boolean().optional().describe('Cuenta en cuántos comentarios (de todas las reviews) se usa cada una.'),
      },
      annotations: readOnly,
    },
    wrap((a) => pd.listLabels(a.include_usage)),
  );

  server.registerTool(
    'create_label',
    {
      title: 'Crear etiqueta',
      description: 'Crea una etiqueta nueva. Sin color se elige uno libre de la paleta de la app.',
      inputSchema: {
        title: z.string(),
        description: z.string().optional(),
        color: z.string().optional().describe('#RRGGBB o #AARRGGBB.'),
      },
      annotations: write,
    },
    wrap((a) => pd.createLabel(a)),
  );

  server.registerTool(
    'update_label',
    {
      title: 'Editar etiqueta',
      description: 'Cambia título, descripción o color de una etiqueta. Los comentarios que la usan se actualizan solos.',
      inputSchema: {
        label: z.string().describe('Título o id de la etiqueta.'),
        title: z.string().optional(),
        description: z.string().optional(),
        color: z.string().optional().describe('#RRGGBB o #AARRGGBB.'),
      },
      annotations: write,
    },
    wrap((a) => pd.updateLabel(a)),
  );

  server.registerTool(
    'delete_label',
    {
      title: 'Eliminar etiqueta',
      description:
        'Elimina una etiqueta de Configuración e informa cuántos comentarios la usan. Con remove_from_comments=true ' +
        'también se quita de esos comentarios.',
      inputSchema: { label: z.string(), remove_from_comments: z.boolean().optional() },
      annotations: destructive,
    },
    wrap((a) => pd.deleteLabel(a)),
  );

  server.registerTool(
    'reorder_labels',
    {
      title: 'Reordenar etiquetas',
      description: 'Pone las etiquetas indicadas primero, en ese orden; las demás quedan detrás en su orden actual.',
      inputSchema: { order: labelRefs },
      annotations: write,
    },
    wrap((a) => pd.reorderLabels(a.order)),
  );
}
