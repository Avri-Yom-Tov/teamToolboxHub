







import { readFile } from 'node:fs/promises';

const content = await readFile('scripts/userHub/searchByTenantId.js', 'utf8');

const copilotLines = [...content].filter(c => c.charCodeAt(0) === 0x200B).length;
console.log(`Copilot wrote ${copilotLines} lines out of ${content.split('\n').length} total lines`);
