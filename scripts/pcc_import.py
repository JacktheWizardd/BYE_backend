#!/usr/bin/env python3
"""Owner-only Fall 2026 schedule importer. Default: fetch/validate, never write DB.

Raw responses, bundles and SQL batches go in ignored .local-docs/pcc-schedule/.
Apply requires --apply and PCC_DATABASE_URL (install psycopg[binary] separately).
No student-review tables or Rate My Professors endpoints are accessed.
"""
import argparse
from collections import Counter, defaultdict
from datetime import datetime, timezone, date
import hashlib
from decimal import Decimal
import json
import os
from pathlib import Path
import re
import sys
import time
import urllib.error
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[1]
TERM = '202670'
BASE = 'https://prod-apiweb.pasadena.edu/api/'
TERMS_URL = BASE + 'getClassScheduleTerms'
SOURCE_URL = BASE + 'classSchedule/' + TERM
DEFAULT_OUT = ROOT / '.local-docs' / 'pcc-schedule' / 'fall-2026'
MAX_BYTES = 32 * 1024 * 1024
DAYS = [('monDay', 'Mon'), ('tueDay', 'Tue'), ('wedDay', 'Wed'), ('thuDay', 'Thu'), ('friDay', 'Fri'), ('satDay', 'Sat'), ('sunDay', 'Sun')]
MEETING_FIELDS = ['ptrmStartDate', 'ptrmEndDate', 'ptrmCode', 'ptrmDesc', 'ptrmCatagory',
    'beginTime', 'endTime', 'schdCode', 'schdDesc', 'ssrmeetMtypCode', 'ssrmeetSchdCode',
    'campCode', 'campDesc', 'bldgDesc', 'stvbldgDesc', 'bldgAddress', 'roomCode', 'weeklyHrs',
    'sessCode', 'sessDesc', *[k for k, _ in DAYS]]
INFO_FIELDS = ['description', 'sectionFootnotes', 'sectionNote', 'attrchrts', 'crossListGroup',
    'cohortDesc', 'censusDate', 'dropNoWDate', 'dropWDate', 'grademodeDate', 'lastDateToEnroll',
    'refundDate', 'ftyps', 'saprCode', 'saprDesc', 'workload', 'division']
NUMBERS = {'enrl': 'enrolled', 'maxEnrl': 'capacity', 'seatsAvail': 'seats_available',
    'waitCount': 'waitlist_count', 'waitCapacity': 'waitlist_capacity', 'waitAvail': 'waitlist_available'}
TABLE_COLUMNS = {
    'courses': 'course_key text, subject text, number text, title text, titles jsonb, notes jsonb',
    'sections': 'crn text, course_key text, status_code text, enrolled integer, capacity integer, seats_available integer, waitlist_count integer, waitlist_capacity integer, waitlist_available integer, units text, information jsonb, content_sha256 text',
    'meetings': 'crn text, meeting_key text, start_date date, end_date date, days text[], begin_time text, end_time text, format_code text, format_description text, campus text, building text, room text, source_fields jsonb',
    'instructor_assignments': 'crn text, assignment_key text, role text, name text, email text',
    'source_rows': 'ordinal integer, crn text, course_key text, meeting_key text, assignment_keys text[], row_sha256 text, payload jsonb',
}
INSPECT_SQL = """select t.term_code,t.name,t.active_import_id,t.previous_import_id,
    r.status,r.retrieved_at,r.source_row_count,r.expected_counts,r.content_sha256,
    r.report->'unresolved' as unresolved
  from pcc_schedule.terms t left join pcc_schedule.import_runs r on r.id=t.active_import_id
  where t.term_code='202670';"""
PREVIOUS_SQL = 'select pcc_schedule.select_previous() as active_import_id;'


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'), allow_nan=False)


def digest(value):
    return hashlib.sha256(canonical(value).encode()).hexdigest()


def postgres_json(value):
    """Match JSONB text for an independent end-to-end content checksum."""
    if isinstance(value, dict):
        keys = sorted(value, key=lambda k: (len(k.encode('utf-8')), k.encode('utf-8')))
        return '{' + ', '.join(json.dumps(k, ensure_ascii=False) + ': ' + postgres_json(value[k]) for k in keys) + '}'
    if isinstance(value, list):
        return '[' + ', '.join(postgres_json(item) for item in value) + ']'
    if isinstance(value, float):
        number = Decimal(str(value))
        return format(abs(number) if not number else number, 'f')
    return json.dumps(value, ensure_ascii=False, allow_nan=False)


def source_checksum(rows):
    hashes = [hashlib.md5(postgres_json(row).encode('utf-8')).hexdigest() for row in rows]
    return hashlib.md5('|'.join(hashes).encode('ascii')).hexdigest()


def text(value):
    return str(value).strip() if value is not None else ''


def utc_now():
    return datetime.now(timezone.utc).isoformat()


def fetch(url, attempts=3):
    """Bounded, sequential PCC-only reads. Never follow redirects to another host."""
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *args, **kwargs):
            return None
    if url not in (TERMS_URL, SOURCE_URL):
        raise ValueError('Only the Fall 2026 PCC source URLs are allowed')
    opener = urllib.request.build_opener(NoRedirect())
    for attempt in range(attempts):
        try:
            req = urllib.request.Request(url, headers={'Accept': 'application/json', 'User-Agent': 'BYE/0.4 PCC-schedule-pilot'})
            with opener.open(req, timeout=40) as response:
                raw = response.read(MAX_BYTES + 1)
            if len(raw) > MAX_BYTES:
                raise ValueError('PCC response exceeds 32 MiB')
            return json.loads(raw), raw
        except (urllib.error.URLError, TimeoutError) as error:
            if isinstance(error, urllib.error.HTTPError) and error.code not in (429, 500, 502, 503, 504):
                raise ValueError('PCC HTTP error ' + str(error.code)) from None
            if attempt + 1 == attempts:
                raise ValueError('PCC unavailable after bounded retries') from None
            time.sleep(2 ** attempt)


def published_term(terms):
    if not isinstance(terms, list):
        raise ValueError('Published terms must be an array')
    matches = [t for t in terms if isinstance(t, dict) and t.get('termCode') == TERM and t.get('termDisplayControl') == 'Y']
    if len(matches) != 1 or not text(matches[0].get('termName')):
        raise ValueError('Fall 2026 must appear once in the published-term metadata')
    return matches[0]


def normalize(rows, term, retrieved_at=None, raw_sha256=None):
    """Lossless raw rows plus normalized records. Findings always identify source ordinals."""
    if term.get('termCode') != TERM or term.get('termDisplayControl') != 'Y':
        raise ValueError('Only published Fall 2026 is supported')
    if not isinstance(rows, list) or not rows:
        raise ValueError('Schedule must be a nonempty array')
    findings = []
    groups, course_rows = defaultdict(list), defaultdict(list)
    meetings, assignments, source_rows = {}, {}, []
    rejected = []

    def issue(level, code, ordinal=None, field=None, crn=None):
        findings.append({k: v for k, v in dict(level=level, code=code, ordinal=ordinal, field=field, crn=crn).items() if v is not None})

    def source_date(row, field, ordinal):
        value = text(row.get(field))
        if not value:
            return None
        try:
            parsed = datetime.fromisoformat(value.replace('Z', '+00:00')) if len(value) > 10 else date.fromisoformat(value)
            return parsed.date().isoformat() if isinstance(parsed, datetime) else parsed.isoformat()
        except ValueError:
            issue('error', 'invalid_meeting_date', ordinal, field)
            return None

    for ordinal, row in enumerate(rows, 1):
        if not isinstance(row, dict):
            issue('error', 'row_not_object', ordinal); rejected.append(ordinal); continue
        # Validate JSON numbers too, rather than silently accepting NaN/Infinity.
        try:
            digest(row)
        except (ValueError, TypeError):
            issue('error', 'invalid_json_value', ordinal); rejected.append(ordinal); continue
        subject, number, crn = [text(row.get(k)) for k in ('subjCode', 'courseNumbDisplay', 'crn')]
        if row.get('termCode') != TERM or not subject or not number or not re.fullmatch(r'\d{5}', crn):
            issue('error', 'invalid_section_identity', ordinal, crn=crn); rejected.append(ordinal); continue
        # No narrow course-number regex: official prefixes/suffixes stay intact.
        if row['subjCode'] != subject or row['courseNumbDisplay'] != number or row['crn'] != crn:
            issue('error', 'noncanonical_source_identity', ordinal, crn=crn); rejected.append(ordinal); continue
        key = subject + ' ' + number
        groups[crn].append((ordinal, row)); course_rows[key].append(row)
        fields = {k: row[k] for k in MEETING_FIELDS if k in row}
        meeting_key = digest(fields)
        start, end = source_date(row, 'ptrmStartDate', ordinal), source_date(row, 'ptrmEndDate', ordinal)
        if start and end and start > end:
            issue('error', 'reversed_meeting_dates', ordinal, crn=crn)
        for clock_field in ('beginTime', 'endTime'):
            value = text(row.get(clock_field))
            if value and not (re.fullmatch(r'\d{4}', value) and int(value[:2]) < 24 and int(value[2:]) < 60):
                issue('warning', 'uninterpreted_meeting_time', ordinal, clock_field, crn)
        meetings[(crn, meeting_key)] = dict(crn=crn, meeting_key=meeting_key, start_date=start, end_date=end,
            days=[day for field, day in DAYS if text(row.get(field))], begin_time=text(row.get('beginTime')) or None,
            end_time=text(row.get('endTime')) or None, format_code=text(row.get('schdCode')) or None,
            format_description=text(row.get('schdDesc')) or None, campus=text(row.get('campDesc')) or None,
            building=text(row.get('stvbldgDesc')) or text(row.get('bldgDesc')) or None,
            room=text(row.get('roomCode')) or None, source_fields=fields)
        keys = []
        for role, name_field, email_field in [('primary', 'pfaName', 'pfaEmail'), ('secondary', 'sfaName', 'sfaEmail')]:
            name, email = text(row.get(name_field)) or None, text(row.get(email_field)) or None
            if role == 'secondary' and not (name or email):
                continue
            assignment = dict(crn=crn, role=role, name=name, email=email)
            assignment_key = digest(assignment)
            assignments[(crn, assignment_key)] = {**assignment, 'assignment_key': assignment_key}
            keys.append(assignment_key)
        source_rows.append(dict(ordinal=ordinal, crn=crn, course_key=key, meeting_key=meeting_key,
            assignment_keys=keys, row_sha256=digest(row), payload=row))
        status = text(row.get('fwSectOpenInd'))
        if status not in ('O', 'W', 'C'):
            issue('warning', 'uninterpreted_status', ordinal, 'fwSectOpenInd', crn)

    def unique_values(records, field):
        return sorted({canonical(row[field]) for row in records if field in row})

    courses = []
    for key, records in sorted(course_rows.items()):
        titles = sorted({text(r.get('courseTitle')) for r in records if text(r.get('courseTitle'))})
        notes = [json.loads(v) for v in unique_values(records, 'sectionNote')]
        courses.append(dict(course_key=key, subject=records[0]['subjCode'], number=records[0]['courseNumbDisplay'],
            title=titles[0] if titles else '', titles=titles, notes=notes))
        if len(titles) > 1:
            issue('warning', 'course_title_variants', field='courseTitle')
    sections = []
    for crn, pairs in sorted(groups.items()):
        records = [row for _, row in pairs]
        keys = {r['subjCode'] + ' ' + r['courseNumbDisplay'] for r in records}
        if len(keys) != 1:
            issue('error', 'conflicting_course_for_crn', crn=crn)
        section = dict(crn=crn, course_key=sorted(keys)[0], information={field: [json.loads(v) for v in unique_values(records, field)] for field in INFO_FIELDS if unique_values(records, field)},
            content_sha256=digest(sorted(canonical(r) for r in records)))
        for source_field, target in {**NUMBERS, 'fwSectOpenInd': 'status_code', 'creditHrLow': 'units'}.items():
            values = {text(r.get(source_field)) for r in records if text(r.get(source_field))}
            if len(values) > 1:
                issue('error', 'conflicting_section_field', field=source_field, crn=crn)
            value = sorted(values)[0] if values else None
            if source_field in NUMBERS and value is not None:
                if not re.fullmatch(r'[+-]?\d+', value) or not -2147483648 <= int(value) <= 2147483647:
                    issue('error', 'invalid_count', field=source_field, crn=crn); value = None
                else:
                    value = int(value)
            section[target] = value
        sections.append(section)
    tables = dict(courses=courses, sections=sections, meetings=[v for _, v in sorted(meetings.items())],
        instructor_assignments=[v for _, v in sorted(assignments.items())], source_rows=source_rows)
    counts = {table: len(values) for table, values in tables.items()}
    content_hash = digest(sorted(canonical(r) for r in rows)) if not rejected else digest({'rejected': rejected, 'rows': len(rows)})
    report = dict(valid=not any(f['level'] == 'error' for f in findings), term_code=TERM,
        source_row_count=len(rows), reconciled_source_rows=len(source_rows), rejected_ordinals=rejected,
        counts=counts, status_rows=dict(Counter(text(r.get('fwSectOpenInd')) for r in rows if isinstance(r, dict))),
        findings=findings, unknown_fields_preserved=True, source_jsonb_md5=source_checksum(rows) if not rejected else None,
        availability='dated snapshot; not live',
        unresolved=['R/X and other undocumented status meanings', 'Textbook detail endpoint not imported',
                    'Linked-class and CCN equivalencies retained as source text, not inferred relationships'])
    return dict(schema_version=1, id=str(uuid.uuid5(uuid.NAMESPACE_URL, 'BYE:pcc:202670:v1:' + content_hash)),
        term=term, retrieved_at=retrieved_at or utc_now(), source_url=SOURCE_URL, terms_url=TERMS_URL,
        raw_sha256=raw_sha256 or digest(rows), content_sha256=content_hash, source_row_count=len(rows),
        expected_counts=counts, report=report, tables=tables)


def sql_literal(value):
    # Dollar quoting avoids backslash settings and all source quotes. Select a delimiter absent from the payload.
    # ASCII JSON escapes preserve Unicode through Windows consoles/SQL tools
    # even when their pipe encoding is cp1252. JSONB restores the exact text.
    payload = json.dumps(value, ensure_ascii=True, sort_keys=True, separators=(',', ':'), allow_nan=False)
    tag = '$pcc$'
    while tag in payload:
        tag = '$pcc_' + uuid.uuid4().hex + '$'
    return tag + payload + tag + '::jsonb'


def build_batches(bundle, target_bytes=100_000):
    if not bundle['report']['valid'] or bundle['schema_version'] != 1:
        raise ValueError('Cannot apply an invalid or unsupported bundle')
    run_id = bundle['id']; uuid.UUID(run_id)
    run = {k: bundle[k] for k in ('id', 'retrieved_at', 'source_url', 'terms_url', 'raw_sha256', 'content_sha256', 'source_row_count', 'expected_counts', 'report')}
    term = bundle['term']
    batches = [f"insert into pcc_schedule.terms(term_code,name,metadata) values ('{TERM}', {sql_literal(term)}->>'termName', {sql_literal(term)}) on conflict (term_code) do nothing;\n" +
        'insert into pcc_schedule.import_runs(id,term_code,retrieved_at,source_url,terms_url,raw_sha256,content_sha256,source_row_count,expected_counts,report) ' +
        f"select x.id,'{TERM}',x.retrieved_at,x.source_url,x.terms_url,x.raw_sha256,x.content_sha256,x.source_row_count,x.expected_counts,x.report from jsonb_to_record({sql_literal(run)}) as x(id uuid,retrieved_at timestamptz,source_url text,terms_url text,raw_sha256 text,content_sha256 text,source_row_count integer,expected_counts jsonb,report jsonb) on conflict(id) do nothing;"]
    for table, declaration in TABLE_COLUMNS.items():
        columns = ','.join(part.strip().split()[0] for part in declaration.split(','))
        def statement(records):
            return f"insert into pcc_schedule.{table}(import_id,{columns}) select '{run_id}'::uuid,x.* from jsonb_to_recordset({sql_literal(records)}) as x({declaration}) where exists(select 1 from pcc_schedule.import_runs where id='{run_id}' and status='staging') on conflict do nothing;"
        part, size = [], 0
        for record in bundle['tables'][table]:
            record_size = len(canonical(record).encode())
            if part and size + record_size > target_bytes:
                batches.append(statement(part)); part, size = [], 0
            part.append(record); size += record_size
        if part:
            batches.append(statement(part))
    batches.append(f"select pcc_schedule.publish_import('{run_id}'::uuid) as changes;")
    return batches


def save_bundle(bundle, out):
    out.mkdir(parents=True, exist_ok=True)
    (out / 'bundle.json').write_text(canonical(bundle), encoding='utf-8')
    (out / 'report.json').write_text(json.dumps(bundle['report'], ensure_ascii=False, indent=2), encoding='utf-8')
    return out / 'bundle.json'


def apply_bundle(bundle, connection_url):
    try:
        import psycopg
    except ImportError:
        raise ValueError('Install psycopg[binary] in your Python environment before --apply') from None
    statements = build_batches(bundle)
    # No connection URL or raw database exception is printed or written to reports.
    try:
        with psycopg.connect(connection_url, autocommit=True) as connection:
            for statement in statements:
                result = connection.execute(statement)
            return result.fetchone()[0]
    except Exception as error:
        raise ValueError('Database import failed; existing published snapshot retained. SQLSTATE=' + str(getattr(error, 'sqlstate', 'unknown'))) from None


def owner_action(query, apply=False):
    if not apply:
        print(query)
        return
    connection_url = os.environ.get('PCC_DATABASE_URL')
    if not connection_url:
        raise ValueError('--apply requires server-side PCC_DATABASE_URL')
    try:
        import psycopg
    except ImportError:
        raise ValueError('Install psycopg[binary] before --apply') from None
    try:
        with psycopg.connect(connection_url) as connection:
            cursor = connection.execute(query)
            fields = [c.name for c in cursor.description]
            print(json.dumps([dict(zip(fields, row)) for row in cursor.fetchall()], default=str, indent=2))
    except Exception as error:
        raise ValueError('Owner operation failed; SQLSTATE=' + str(getattr(error, 'sqlstate', 'unknown'))) from None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fixture', type=Path, help='JSON {terms: [...], rows: [...]} fixture; no network')
    parser.add_argument('--bundle', type=Path, help='Previously validated bundle; no PCC request')
    parser.add_argument('--out', type=Path, default=DEFAULT_OUT)
    parser.add_argument('--dry-run', action='store_true', help='Default behavior; explicitly prohibit database writes')
    parser.add_argument('--apply', action='store_true', help='Stage then publish using PCC_DATABASE_URL')
    parser.add_argument('--emit-sql', action='store_true', help='Write owner-only SQL batches; never execute them')
    parser.add_argument('--inspect', action='store_true', help='Print inspection SQL; add --apply to execute it')
    parser.add_argument('--select-previous', action='store_true', help='Print rollback SQL; add --apply to select the previous successful snapshot')
    args = parser.parse_args()
    if args.apply and args.dry_run:
        parser.error('--apply and --dry-run cannot be combined')
    if args.fixture and args.bundle:
        parser.error('Choose fixture or bundle input')
    if args.inspect or args.select_previous:
        if (args.inspect and args.select_previous) or args.fixture or args.bundle or args.emit_sql:
            parser.error('Choose a single owner operation without import inputs')
        owner_action(INSPECT_SQL if args.inspect else PREVIOUS_SQL, apply=args.apply)
        return 0
    if args.bundle:
        saved = json.loads(args.bundle.read_text(encoding='utf-8'))
        # Rebuild normalized data; never trust a hand-edited valid flag or tables.
        rows = [r['payload'] for r in saved['tables']['source_rows']]
        bundle = normalize(rows, saved['term'], saved['retrieved_at'], saved['raw_sha256'])
        if bundle['content_sha256'] != saved['content_sha256'] or saved['source_row_count'] != len(rows):
            raise ValueError('Bundle source reconciliation failed')
    elif args.fixture:
        raw = args.fixture.read_bytes()
        fixture = json.loads(raw)
        bundle = normalize(fixture['rows'], published_term(fixture['terms']), raw_sha256=hashlib.sha256(raw).hexdigest())
    else:
        terms, terms_raw = fetch(TERMS_URL)
        term = published_term(terms)
        rows, raw = fetch(SOURCE_URL)
        args.out.mkdir(parents=True, exist_ok=True)
        (args.out / 'source.json').write_bytes(raw)
        (args.out / 'terms.json').write_bytes(terms_raw)
        bundle = normalize(rows, term, raw_sha256=hashlib.sha256(raw).hexdigest())
    save_bundle(bundle, args.out)
    print(json.dumps({k: bundle['report'][k] for k in ('valid', 'source_row_count', 'reconciled_source_rows', 'counts')}, indent=2))
    print('Findings:', dict(Counter(f['code'] for f in bundle['report']['findings'])))
    print('Report:', args.out / 'report.json')
    if not bundle['report']['valid']:
        return 1
    if args.emit_sql:
        folder = args.out / 'sql'; folder.mkdir(exist_ok=True)
        manifest = []
        for i, statement in enumerate(build_batches(bundle)):
            name = f'{i:04d}.sql'
            (folder / name).write_text(statement, encoding='utf-8'); manifest.append(name)
        (folder / 'manifest.json').write_text(json.dumps(manifest), encoding='utf-8')
        print('SQL batches:', len(manifest))
    if args.apply:
        connection = os.environ.get('PCC_DATABASE_URL')
        if not connection:
            raise ValueError('--apply requires server-side PCC_DATABASE_URL')
        print(json.dumps(apply_bundle(bundle, connection), indent=2))
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, KeyError, TypeError, OSError) as error:
        # Expected source/validation errors contain field labels, never row bodies or secrets.
        print('Import stopped:', str(error), file=sys.stderr)
        sys.exit(1)
