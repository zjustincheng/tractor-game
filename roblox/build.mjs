import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath, URL } from 'node:url';
import console from 'node:console';
const root = new URL('./', import.meta.url);
const escape = (text) =>
  text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
let id = 0;
const item = (className, name, children = '', properties = '') =>
  `<Item class="${className}" referent="RBX${++id}"><Properties><string name="Name">${name}</string>${properties}</Properties>${children}</Item>`;
const source = async (path, className, name) =>
  item(
    className,
    name,
    '',
    `<ProtectedString name="Source">${escape(await readFile(new URL(path, root), 'utf8'))}</ProtectedString>`,
  );
const shared = item(
  'Folder',
  'Tractor',
  (await source('src/shared/Cards.luau', 'ModuleScript', 'Cards')) +
    (await source('src/shared/Catalog.luau', 'ModuleScript', 'Catalog')) +
    (await source(
      'src/shared/TableLayout.luau',
      'ModuleScript',
      'TableLayout',
    )) +
    (await source('src/shared/Structures.luau', 'ModuleScript', 'Structures')) +
    (await source('src/shared/PlayRules.luau', 'ModuleScript', 'PlayRules')) +
    (await source('src/shared/Scoring.luau', 'ModuleScript', 'Scoring')),
);
// Folder names match default.project.json so Rojo syncs onto these instances
// instead of adding a second copy of each script.
const server = item(
  'Folder',
  'TractorServer',
  (await source('src/server/Practice.luau', 'ModuleScript', 'Practice')) +
    (await source(
      'src/server/TrainedBots.luau',
      'ModuleScript',
      'TrainedBots',
    )) +
    (await source(
      'src/server/ChampionModel.luau',
      'ModuleScript',
      'ChampionModel',
    )) +
    (await source(
      'src/server/Persistence.luau',
      'ModuleScript',
      'Persistence',
    )) +
    (await source('src/server/Matchmaker.luau', 'ModuleScript', 'Matchmaker')) +
    (await source(
      'src/server/CrossServer.luau',
      'ModuleScript',
      'CrossServer',
    )) +
    (await source('src/server/Main.server.luau', 'Script', 'Main')),
);
const client = item(
  'Folder',
  'TractorClient',
  (await source('src/client/Reactions.luau', 'ModuleScript', 'Reactions')) +
    (await source('src/client/Main.client.luau', 'LocalScript', 'Main')),
);
const floor = item(
  'Part',
  'Floor',
  '',
  '<bool name="Anchored">true</bool><Vector3 name="size"><X>120</X><Y>1</Y><Z>120</Z></Vector3>',
);
const spawn = item(
  'SpawnLocation',
  'Spawn',
  '',
  '<bool name="Anchored">true</bool><CoordinateFrame name="CFrame"><X>0</X><Y>2</Y><Z>20</Z><R00>1</R00><R01>0</R01><R02>0</R02><R10>0</R10><R11>1</R11><R12>0</R12><R20>0</R20><R21>0</R21><R22>1</R22></CoordinateFrame>',
);
const xml = `<roblox version="4">${item('Workspace', 'Workspace', floor + spawn)}${item('ReplicatedStorage', 'ReplicatedStorage', shared)}${item('ServerScriptService', 'ServerScriptService', server)}${item('StarterPlayer', 'StarterPlayer', item('StarterPlayerScripts', 'StarterPlayerScripts', client))}</roblox>`;
await mkdir(new URL('dist/', root), { recursive: true });
const output = new URL('dist/Tractor.rbxlx', root);
await writeFile(output, xml);
console.log(`Built ${fileURLToPath(output)}`);
