import copy
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('pcc_import', ROOT / 'scripts/pcc_import.py')
pcc = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(pcc)
FIXTURE = Path(__file__).parent / 'fixtures/pcc-fall-2026.json'


class ImportTests(unittest.TestCase):
    def setUp(self):
        data = json.loads(FIXTURE.read_text())
        self.rows, self.term = data['rows'], pcc.published_term(data['terms'])

    def bundle(self):
        return pcc.normalize(self.rows, self.term, '2026-10-17T12:00:00+00:00')

    def test_full_source_reconciliation_and_unknown_fields(self):
        bundle = self.bundle()
        self.assertTrue(bundle['report']['valid'])
        self.assertEqual(bundle['expected_counts'], dict(courses=5, sections=5, meetings=7, instructor_assignments=6, source_rows=7))
        self.assertEqual([r['payload'] for r in bundle['tables']['source_rows']], self.rows)
        self.assertTrue(bundle['tables']['source_rows'][0]['payload']['unknownFutureField']['retained'])

    def test_suffixes_ccn_and_official_labels_never_merge(self):
        self.assertEqual({c['course_key'] for c in self.bundle()['tables']['courses']}, {'MATH 005A', 'MATH 005AH', 'MATH 005AL', 'ACCT 001A', 'ENGL C1000H'})

    def test_closed_status_is_not_inferred_from_available_seats(self):
        section = next(s for s in self.bundle()['tables']['sections'] if s['crn'] == '80206')
        self.assertEqual((section['status_code'], section['enrolled'], section['capacity'], section['seats_available']), ('C', 21, 28, 7))
        self.assertEqual(section['waitlist_available'], 7)

    def test_meetings_preserve_component_dates(self):
        meetings = [m for m in self.bundle()['tables']['meetings'] if m['crn'] == '81016']
        self.assertEqual(len(meetings), 3)
        self.assertEqual({m['start_date'] for m in meetings}, {'2026-09-29', '2026-10-27', '2026-08-24'})
        self.assertEqual(next(m for m in meetings if m['start_date'] == '2026-08-24')['days'], [])

    def test_instructor_assignments_are_section_scoped_and_keep_secondary(self):
        roster = self.bundle()['tables']['instructor_assignments']
        self.assertEqual({a['role'] for a in roster if a['crn'] == '80206'}, {'primary', 'secondary'})
        self.assertEqual(len([a for a in roster if a['name'] == 'Alex Example']), 3)
        self.assertIsNone(next(a for a in roster if a['crn'] == '90003')['name'])

    def test_notes_and_html_are_preserved_as_data(self):
        info = next(s for s in self.bundle()['tables']['sections'] if s['crn'] == '80206')['information']
        self.assertIn('80214', info['sectionFootnotes'][0])
        self.assertEqual(info['sectionNote'], ['<b>Prerequisite:</b> MATH 008'])
        self.assertIn('lastDateToEnroll', info)

    def test_unknown_statuses_are_retained_with_findings(self):
        bundle = self.bundle()
        self.assertEqual({s['status_code'] for s in bundle['tables']['sections']}, {'C', 'R', 'X', 'W'})
        self.assertEqual(sum(f['code'] == 'uninterpreted_status' for f in bundle['report']['findings']), 2)

    def test_missing_counts_stay_unknown_and_negative_source_values_retained(self):
        self.rows[-1]['seatsAvail'] = '-2'
        section = next(s for s in self.bundle()['tables']['sections'] if s['crn'] == '90003')
        self.assertIsNone(section['capacity']); self.assertEqual(section['seats_available'], -2)

    def test_reordered_rows_produce_same_snapshot_and_section_hashes(self):
        first = self.bundle()
        self.rows.reverse(); second = self.bundle()
        self.assertEqual(first['id'], second['id'])
        self.assertEqual(first['tables']['sections'], second['tables']['sections'])

    def test_duplicate_rows_are_raw_preserved_without_duplicate_meetings(self):
        self.rows.append(copy.deepcopy(self.rows[0]))
        bundle = self.bundle()
        self.assertEqual(bundle['expected_counts']['source_rows'], 8)
        self.assertEqual(bundle['expected_counts']['meetings'], 7)

    def test_conflicting_identity_and_counts_block_publication(self):
        duplicate = copy.deepcopy(self.rows[0]); duplicate['enrl'] = '22'
        self.rows.append(duplicate)
        bundle = self.bundle()
        self.assertFalse(bundle['report']['valid'])
        self.assertRaises(ValueError, pcc.build_batches, bundle)
        duplicate['courseNumbDisplay'] = '005B'
        self.assertIn('conflicting_course_for_crn', [f['code'] for f in self.bundle()['report']['findings']])

    def test_wrong_term_uses_term_code_not_default_term(self):
        self.assertTrue(self.bundle()['report']['valid'])
        self.rows[0]['termCode'] = '202630'
        self.assertFalse(self.bundle()['report']['valid'])

    def test_malformed_rows_and_dates_are_accounted_for(self):
        self.rows[0]['ptrmStartDate'] = 'invalid'
        self.rows += [None, {'termCode': pcc.TERM}]
        report = self.bundle()['report']
        self.assertFalse(report['valid'])
        self.assertEqual(report['reconciled_source_rows'] + len(report['rejected_ordinals']), report['source_row_count'])

    def test_no_empty_or_unpublished_import(self):
        self.assertRaises(ValueError, pcc.normalize, [], self.term)
        self.assertRaises(ValueError, pcc.published_term, [])
        self.assertRaises(ValueError, pcc.published_term, [{**self.term, 'termDisplayControl': 'N'}])

    def test_invalid_numeric_value_prevents_apply(self):
        self.rows[0]['seatsAvail'] = 'unknown'
        self.assertFalse(self.bundle()['report']['valid'])
        self.assertRaises(ValueError, pcc.build_batches, self.bundle())

    def test_owner_actions_print_sql_without_writing_or_fetching(self):
        with patch.object(sys, 'argv', ['pcc_import.py', '--inspect']), patch.object(pcc, 'fetch') as fetch, patch('builtins.print') as output:
            self.assertEqual(pcc.main(), 0)
            fetch.assert_not_called(); output.assert_called_once_with(pcc.INSPECT_SQL)
        with patch.object(sys, 'argv', ['pcc_import.py', '--select-previous']), patch('builtins.print') as output:
            self.assertEqual(pcc.main(), 0)
            output.assert_called_once_with(pcc.PREVIOUS_SQL)

    def test_apply_cannot_be_combined_with_dry_run(self):
        with patch.object(sys, 'argv', ['pcc_import.py', '--apply', '--dry-run']), patch('sys.stderr'), self.assertRaises(SystemExit):
            pcc.main()

    def test_sql_quoting_source_content_cannot_escape_literal(self):
        self.rows[0]['sectionFootnotes'] = "'$pcc$; drop table public.reviews; -- \\"
        batches = pcc.build_batches(self.bundle(), target_bytes=1200)
        self.assertGreater(len(batches), 8)
        self.assertTrue(any('$pcc_' in q for q in batches))
        self.assertTrue(all('create ' not in q.lower() for q in batches))

    def test_unicode_sql_is_ascii_safe_and_has_independent_payload_checksum(self):
        self.rows[0]['description'] = 'Caf\u00e9 \u2014 \U0001f393'
        bundle = self.bundle()
        self.assertTrue(all(sql.isascii() for sql in pcc.build_batches(bundle)))
        self.assertEqual(bundle['report']['source_jsonb_md5'], pcc.source_checksum(self.rows))
        self.rows[0]['description'] = 'Caf?'
        self.assertNotEqual(self.bundle()['report']['source_jsonb_md5'], bundle['report']['source_jsonb_md5'])

    def test_dry_run_writes_no_database_and_never_requests_rmp(self):
        scratch = ROOT / '.local-docs' / 'pcc-schedule-tools'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as folder, patch.object(sys, 'argv', ['pcc_import.py', '--fixture', str(FIXTURE), '--out', folder, '--dry-run']), patch.object(pcc, 'apply_bundle') as apply, patch.object(pcc, 'fetch') as fetch:
            self.assertEqual(pcc.main(), 0)
            apply.assert_not_called(); fetch.assert_not_called()
            self.assertTrue((Path(folder) / 'report.json').exists())


if __name__ == '__main__':
    unittest.main()
