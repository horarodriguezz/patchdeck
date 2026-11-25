import assert from 'node:assert/strict';
import { promises as fs } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';

const here = path.dirname(fileURLToPath(import.meta.url));

test('server speaks MCP over stdio', async () => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'patchdeck-mcp-e2e-'));
  const transport = new StdioClientTransport({
    command: process.execPath,
    args: [path.join(here, '..', 'src', 'index.js')],
    env: { ...process.env, PATCHDECK_CONFIG_DIR: path.join(dir, 'c'), PATCHDECK_DATA_DIR: path.join(dir, 'd') } as Record<
      string,
      string
    >,
    stderr: 'ignore',
  });
  const client = new Client({ name: 'test', version: '0' });
  await client.connect(transport);
  try {
    const { tools } = await client.listTools();
    const names = tools.map((t) => t.name).sort();
    for (const n of ['add_comment', 'create_label', 'delete_label', 'get_patch', 'list_labels', 'list_reviews', 'reorder_labels']) {
      assert.ok(names.includes(n), `missing tool ${n}`);
    }
    const created = await client.callTool({ name: 'create_review', arguments: { title: 'E2E' } });
    assert.match((created.content as { text: string }[])[0]!.text, /"title": "E2E"/);

    const bad = await client.callTool({ name: 'get_review', arguments: { review: 'nada' } });
    assert.equal(bad.isError, true);
    assert.match((bad.content as { text: string }[])[0]!.text, /No encuentro la review/);
  } finally {
    await client.close();
  }
});
