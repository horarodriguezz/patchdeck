#!/usr/bin/env node
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';

import { Patchdeck } from './ops.js';
import { pathsFromEnv } from './paths.js';
import { Store } from './store.js';
import { registerTools } from './tools.js';

const paths = pathsFromEnv();
const server = new McpServer(
  { name: 'patchdeck', version: '0.1.0' },
  {
    instructions:
      'Patchdeck es una app de escritorio para revisar git patches. Este servidor lee y escribe sus datos: reviews, ' +
      'patches, comentarios anclados a líneas, etiquetas, contexto y notas. La app abierta recarga sola los cambios. ' +
      'Flujo típico: list_reviews → get_review → get_patch (números de línea) → add_comment con etiquetas existentes ' +
      '(list_labels). Los comentarios se escriben en el idioma de la review.',
  },
);
registerTools(server, new Patchdeck(new Store(paths)));

await server.connect(new StdioServerTransport());
console.error(`patchdeck-mcp: datos en ${paths.dataDir}, configuración en ${paths.configDir}`);
