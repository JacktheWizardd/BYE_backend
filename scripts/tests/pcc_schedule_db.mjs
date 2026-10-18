// Real PostgreSQL engine, isolated in memory. No network/database credentials used.
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { execFileSync } from 'node:child_process'
import path from 'node:path'
import { pathToFileURL, fileURLToPath } from 'node:url'
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..')
const modulePath = process.env.PCC_PGLITE_MODULE || path.join(root, '.local-docs/pcc-schedule-tools/node_modules/@electric-sql/pglite/dist/index.js')
const { PGlite } = await import(pathToFileURL(modulePath).href)
const db = new PGlite(), python = process.env.PCC_PYTHON || 'python3'
const fixture = path.join(root, 'scripts/tests/fixtures/pcc-fall-2026.json')
let checks = 0
const query = async (sql, params = []) => (await db.query(sql, params)).rows
async function check(label, work) { await work(); checks++; console.log('PASS', label) }
function bundleSQL(change = '') {
  const code = `import sys,json; sys.path.insert(0,${JSON.stringify(path.join(root, 'scripts'))}); import pcc_import as p; f=json.load(open(${JSON.stringify(fixture).replaceAll('\\\\','/')})); rows=f['rows']; ${change || 'pass'}; b=p.normalize(rows,p.published_term(f['terms'])); print(json.dumps({'bundle': b, 'sql': p.build_batches(b)}))`
  return JSON.parse(execFileSync(python, ['-I', '-c', code], { encoding: 'utf8', maxBuffer: 4 * 1024 * 1024 }))
}
await db.exec(`create role anon; create role authenticated; create role service_role bypassrls;
  create schema auth; create function auth.uid() returns uuid language sql as 'select null::uuid';
  create table auth.users(id uuid primary key);`)
await db.exec(await readFile(path.join(root, 'supabase/schema.sql'), 'utf8'))
await db.exec(`insert into public.professors(first_name,last_name) values ('Review','Sentinel');
  insert into public.courses(code,title) values ('SENTINEL 001','Existing review catalog');
  grant usage on schema public to anon; grant select on public.courses to anon;`)
const baseline = await query("select count(*)::int as n from public.courses")
await db.exec(await readFile(path.join(root, 'supabase/004_pcc_schedule.sql'), 'utf8'))
await db.exec(await readFile(path.join(root, 'supabase/005_pcc_schedule_source_integrity.sql'), 'utf8'))
const first = bundleSQL()
await check('migration leaves existing review tables and catalog intact', async () => {
  assert.deepEqual(await query('select count(*)::int as n from public.courses'), baseline)
  assert.equal((await query('select count(*)::int as n from public.reviews'))[0].n, 0)
  await db.exec('set role anon')
  assert.equal((await query('select count(*)::int as n from public.courses'))[0].n, 1)
  await db.exec('reset role')
})
await check('staging never publishes partially loaded snapshots', async () => {
  await db.exec(first.sql[0])
  assert.equal((await query('select active_import_id from pcc_schedule.terms'))[0].active_import_id, null)
  await assert.rejects(db.exec(first.sql.at(-1)), /Incomplete import/)
})
await check('complete load publishes every source row and separate meeting', async () => {
  for (const sql of first.sql.slice(1)) await db.exec(sql)
  assert.equal((await query('select active_import_id from pcc_schedule.terms'))[0].active_import_id, first.bundle.id)
  assert.equal((await query('select count(*)::int as n from pcc_schedule.source_rows'))[0].n, 7)
  assert.equal((await query("select count(*)::int as n from pcc_schedule.meetings where crn='81016'"))[0].n, 3)
})
await check('ordinary roles cannot read, write, publish or roll back private records', async () => {
  for (const role of ['anon', 'authenticated', 'service_role']) {
    await db.exec(`set role ${role}`)
    for (const sql of ['select * from pcc_schedule.source_rows', "insert into pcc_schedule.terms(term_code,name,metadata) values ('202670','x','{}')", `select pcc_schedule.publish_import('${first.bundle.id}')`, 'select pcc_schedule.select_previous()']) {
      await assert.rejects(db.exec(sql), /permission denied/)
    }
    await db.exec('reset role')
  }
})
await check('all schedule tables have RLS with no public policies', async () => {
  const tables = await query("select relrowsecurity from pg_class join pg_namespace on relnamespace=pg_namespace.oid where nspname='pcc_schedule' and relkind='r'")
  assert.equal(tables.length, 7); assert.ok(tables.every(t => t.relrowsecurity))
  assert.equal((await query("select count(*)::int as n from pg_policies where schemaname='pcc_schedule'"))[0].n, 0)
})
await check('repeating the same import is idempotent', async () => {
  for (const sql of first.sql) await db.exec(sql)
  assert.equal((await query('select count(*)::int as n from pcc_schedule.import_runs'))[0].n, 1)
  assert.equal((await query('select count(*)::int as n from pcc_schedule.source_rows'))[0].n, 7)
})
await check('published snapshot records cannot be modified', async () => {
  await assert.rejects(db.exec("update pcc_schedule.sections set status_code='O'"), /immutable/)
  await assert.rejects(db.exec('delete from pcc_schedule.source_rows'), /immutable/)
})
await check('reordered raw rows select the same snapshot without duplicating records', async () => {
  const reordered = bundleSQL('rows.reverse()')
  assert.equal(reordered.bundle.id, first.bundle.id)
  for (const sql of reordered.sql) await db.exec(sql)
  assert.equal((await query('select count(*)::int as n from pcc_schedule.source_rows'))[0].n, 7)
})
const next = bundleSQL("rows[0]['seatsAvail']='6'; rows[0]['enrl']='22'; rows.pop(); rows.append({**rows[-1], 'crn':'90004', 'courseNumbDisplay':'005BE'})")
await check('an interrupted later import leaves the previous snapshot active', async () => {
  for (const sql of next.sql.slice(0, 3)) await db.exec(sql)
  await assert.rejects(db.exec(next.sql.at(-1)), /Incomplete import/)
  assert.equal((await query('select active_import_id from pcc_schedule.terms'))[0].active_import_id, first.bundle.id)
})
await check('publication reports added, changed and removed CRNs', async () => {
  for (const sql of next.sql) await db.exec(sql)
  const result = (await query('select changes from pcc_schedule.import_runs where id=$1', [next.bundle.id]))[0].changes
  assert.deepEqual(result, { added: ['90004'], removed: ['90003'], changed: ['80206'] })
})
await check('previous successful snapshot can be selected without deleting data', async () => {
  assert.equal((await query('select pcc_schedule.select_previous() as id'))[0].id, first.bundle.id)
  assert.equal((await query('select count(*)::int as n from pcc_schedule.source_rows'))[0].n, 14)
})
await check('an older fetch cannot replace newer published data', async () => {
  // Point forward again, then stage a different snapshot with an earlier retrieval date.
  await query('select pcc_schedule.select_previous()')
  const older = bundleSQL("rows[0]['waitCount']='1'")
  for (const sql of older.sql.slice(0, -1)) await db.exec(sql)
  await query("update pcc_schedule.import_runs set retrieved_at='2020-01-01' where id=$1", [older.bundle.id])
  await assert.rejects(db.exec(older.sql.at(-1)), /Older import/)
  assert.equal((await query('select active_import_id from pcc_schedule.terms'))[0].active_import_id, next.bundle.id)
})
await check('publication rejects a source row assigned to the wrong course', async () => {
  const invalid = bundleSQL("rows[0]['waitCount']='2'")
  for (const sql of invalid.sql.slice(0, -1)) await db.exec(sql)
  await query("update pcc_schedule.source_rows set course_key='MATH 005AL' where import_id=$1 and ordinal=1", [invalid.bundle.id])
  await assert.rejects(db.exec(invalid.sql.at(-1)), /reconciliation failed/)
  assert.equal((await query('select active_import_id from pcc_schedule.terms'))[0].active_import_id, next.bundle.id)
})
await check('source HTML is inert data and unknown fields survive PostgreSQL storage', async () => {
  const value = (await query('select payload from pcc_schedule.source_rows where import_id=$1 and ordinal=1', [first.bundle.id]))[0].payload
  assert.equal(value.unknownFutureField.retained, true)
  assert.equal(value.sectionNote, '<b>Prerequisite:</b> MATH 008')
})
await check('Unicode survives ASCII SQL transport and mismatched source text blocks publication', async () => {
  const unicode = bundleSQL("rows[0]['description']='Caf\\u00e9 \\u2014 \\U0001f393'")
  for (const sql of unicode.sql.slice(0, -1)) await db.exec(sql)
  await query("update pcc_schedule.source_rows set payload=jsonb_set(payload,'{description}','\"DAMAGED\"'::jsonb) where import_id=$1 and ordinal=1", [unicode.bundle.id])
  await assert.rejects(db.exec(unicode.sql.at(-1)), /checksum mismatch/)
  assert.equal((await query('select active_import_id from pcc_schedule.terms'))[0].active_import_id, next.bundle.id)
  await query('update pcc_schedule.source_rows set payload=$1::jsonb where import_id=$2 and ordinal=1', [JSON.stringify(unicode.bundle.tables.source_rows[0].payload), unicode.bundle.id])
  await db.exec(unicode.sql.at(-1))
})
console.log(`${checks} PostgreSQL integration scenarios passed`)
await db.close()

// Optional full source rehearsal, still isolated and offline. The bundle stays ignored.
if (process.argv[2]) {
  const folder = path.resolve(process.argv[2]), pilot = new PGlite()
  const bundle = JSON.parse(await readFile(path.join(folder, 'bundle.json'), 'utf8'))
  await pilot.exec('create role anon; create role authenticated; create role service_role bypassrls;')
  await pilot.exec(await readFile(path.join(root, 'supabase/004_pcc_schedule.sql'), 'utf8'))
  await pilot.exec(await readFile(path.join(root, 'supabase/005_pcc_schedule_source_integrity.sql'), 'utf8'))
  const manifest = JSON.parse(await readFile(path.join(folder, 'sql/manifest.json'), 'utf8'))
  for (const name of manifest) await pilot.exec(await readFile(path.join(folder, 'sql', name), 'utf8'))
  const actual = {}
  for (const table of Object.keys(bundle.expected_counts)) actual[table] = (await pilot.query(`select count(*)::int as n from pcc_schedule.${table}`)).rows[0].n
  assert.deepEqual(actual, bundle.expected_counts)
  const status = (await pilot.query('select status from pcc_schedule.import_runs')).rows[0].status
  assert.equal(status, 'published')
  console.log('PASS complete Fall 2026 source rehearsal:', JSON.stringify(actual))
  await pilot.close()
}
