#!/usr/bin/env node
/**
 * Smoke test for Microsoft BASIC V1.1 on bw-board's M6502Machine.
 *
 * Boots the ROM, answers the MEMORY SIZE? and TERMINAL WIDTH? prompts,
 * waits for the OK prompt, types PRINT 2+2, and expects 4.
 */
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { M6502Machine, EATER6502 } from '../../bw-board/src/m6502-machine.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const romPath = join(__dirname, '..', 'basic.rom');
const rom = readFileSync(romPath);

let out = '';
const m = new M6502Machine(EATER6502, {
    onSerial: (byte) => { out += String.fromCharCode(byte); },
});

m.loadRom(rom, 0x8000);
m.reset();

const type = (s) => {
    for (const ch of s) {
        m.chips.acia1.rxPush(ch.charCodeAt(0));
        m.advanceToMs(m.tMs + (ch === '\r' ? 500 : 30));
    }
};

// Boot - BASIC should print "MEMORY SIZE?" prompt
m.advanceToMs(500);
console.log('--- After 500ms boot ---');
console.log(JSON.stringify(out));

// Answer MEMORY SIZE? with blank (use default - probe RAM)
type('\r');
m.advanceToMs(m.tMs + 2000);
console.log('--- After MEMORY SIZE answer ---');
console.log(JSON.stringify(out));

// Answer TERMINAL WIDTH? with blank (use default 72)
type('\r');
m.advanceToMs(m.tMs + 2000);
console.log('--- After TERMINAL WIDTH answer ---');
console.log(JSON.stringify(out));

// Now should see bytes free + banner + OK
// Type PRINT 2+2
type('PRINT 2+2\r');
m.advanceToMs(m.tMs + 2000);
console.log('--- After PRINT 2+2 ---');
console.log(JSON.stringify(out));

// Checks
const checks = [];
const expect = (what, ok, detail) => {
    checks.push({ what, ok, detail });
};

expect('MEMORY SIZE prompt', /MEMORY SIZE/i.test(out), out.slice(0, 100));
expect('WIDTH prompt', /WIDTH/i.test(out));
expect('BYTES FREE', /BYTES FREE/i.test(out));
expect('OK prompt', /\nOK\r?\n/.test(out) || /\rOK\r?\n/.test(out));
expect('PRINT 2+2 = 4', /\n\s+4\s/.test(out));

// Test a stored program
type('10 FOR I=1 TO 3\r');
type('20 PRINT "HI";I\r');
type('30 NEXT I\r');
type('RUN\r');
m.advanceToMs(m.tMs + 3000);
console.log('--- After RUN ---');
console.log(JSON.stringify(out.slice(-200)));

expect('stored program runs', /HI\s+1/.test(out) && /HI\s+2/.test(out) && /HI\s+3/.test(out));

let bad = 0;
for (const c of checks) {
    const suffix = c.detail ? ` (${c.detail})` : '';
    console.log(`${c.ok ? 'ok ' : 'FAIL'}  ${c.what}${c.ok ? '' : suffix}`);
    if (!c.ok) bad++;
}
if (!bad) {
    console.log(`\nMicrosoft BASIC is alive (${(m.tMs / 1000).toFixed(1)} machine-seconds).`);
}
process.exit(bad ? 1 : 0);
