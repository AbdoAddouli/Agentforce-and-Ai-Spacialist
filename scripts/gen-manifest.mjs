// Regenerates manifest/package.xml from what is actually on disk, so the
// manifest can never drift from force-app again.
import { readdirSync, statSync, writeFileSync, existsSync } from 'node:fs';
import { join, basename } from 'node:path';

const DEF = join(process.cwd(), 'force-app', 'main', 'default');

// Directory name -> Metadata API type name. These are not the same thing:
// a folder called "classes" holds ApexClass members.
// ext is the suffix a member file ends with; metaSuffix is the companion
// file to skip. Flow has no separate companion, so its ext is the meta name.
const TYPES = [
  ['classes', '.cls', '-meta.xml', 'ApexClass'],
  ['triggers', '.trigger', '-meta.xml', 'ApexTrigger'],
  ['objects', '.object', '-object-meta.xml', 'CustomObject'],
  ['flows', '.flow-meta.xml', null, 'Flow'],
  ['permissionsets', '.permissionset', '-meta.xml', 'PermissionSet'],
  ['approvalProcesses', '.approvalProcess', '-meta.xml', 'ApprovalProcess'],
  ['email', '.email', '-meta.xml', 'EmailTemplate'],
  ['platformEvents', '.platformEvent', '-meta.xml', 'PlatformEvent'],
  ['reports', '.report', '-meta.xml', 'Report'],
  ['dashboards', '.dashboard', '-meta.xml', 'Dashboard'],
  ['tabs', '.tab', '-meta.xml', 'CustomTab'],
  ['flexipages', '.flexipage', '-meta.xml', 'FlexiPage'],
  ['lwc', '.js-meta.xml', null, 'LightningComponentBundle'],
];

function listFiles(dir) {
  if (!existsSync(dir)) return [];
  const out = [];
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) out.push(...listFiles(full));
    else out.push(full);
  }
  return out;
}

const blocks = [];
for (const [dir, ext, metaSuffix, apiType] of TYPES) {
  const files = listFiles(join(DEF, dir));
  const members = files
    .filter((f) => f.endsWith(ext))
    .filter((f) => !metaSuffix || !basename(f).endsWith(metaSuffix))
    // The member is the component name only: the directory is the type.
    .map((f) => basename(f).slice(0, -ext.length))
    .sort();
  if (members.length) {
    blocks.push(
      `    <types>\n${members.map((m) => `        <members>${m}</members>`).join('\n')}\n        <name>${apiType}</name>\n    </types>`
    );
  }
}

const xml =
  `<?xml version="1.0" encoding="UTF-8"?>\n` +
  `<Package xmlns="http://soap.sforce.com/2006/04/metadata">\n` +
  blocks.join('\n') + '\n' +
  `    <version>68.0</version>\n` +
  `</Package>\n`;

writeFileSync(join(process.cwd(), 'manifest', 'package.xml'), xml, 'utf8');
console.log(blocks.map((b) => b.match(/<name>(.+)<\/name>/)[1]).join(', '));
