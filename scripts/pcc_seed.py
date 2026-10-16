#!/usr/bin/env python3
"""Build pcc_seed.sql (courses and professors) from PCC's public class schedule.

Reads the same PCC schedule API the app uses (one request per published term,
paced a few seconds apart). Makes no RMP requests and never connects to
Supabase: paste the output into the Supabase SQL Editor yourself. Re-running
the SQL is safe, because rows that already exist are skipped.

    python3 scripts/pcc_seed.py                      # live PCC schedule
    python3 scripts/pcc_seed.py --fixture rows.json  # offline, one term's rows
"""
import argparse
import json
import os
import ssl
import sys
import time
import urllib.request
from pathlib import Path

API = "https://prod-apiweb.pasadena.edu/api/"
HEADERS = {"Accept": "application/json", "User-Agent": "BYE/0.3"}
PAUSE_SECONDS = 3
TIMEOUT_SECONDS = 120
SUFFIXES = {"jr", "jr.", "sr", "sr.", "ii", "iii", "iv"}
# Lowercase words that start a surname ("De La O", "van Gogh", "Mc Cord", "St. Clair").
PARTICLES = {"de", "del", "della", "la", "le", "van", "von", "der", "den", "di", "da", "du",
             "dos", "das", "el", "al", "ben", "bin", "mc", "mac", "st", "st.", "o"}
DEFAULT_OUT = Path(__file__).resolve().parent.parent / "pcc_seed.sql"
MAC_CERTS = "/etc/ssl/cert.pem"


def tls_context():
    # python.org's Python ignores the macOS certificate store until its
    # "Install Certificates" step runs, so also trust the system bundle.
    context = ssl.create_default_context()
    if os.path.exists(MAC_CERTS):
        context.load_verify_locations(MAC_CERTS)
    return context


TLS = tls_context()


def fetch(path, attempts=3):
    """GET a PCC API path, retrying slow or dropped responses with a growing pause."""
    request = urllib.request.Request(API + path, headers=HEADERS)
    for attempt in range(1, attempts + 1):
        try:
            # Older terms can take a while to generate on PCC's side.
            with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS, context=TLS) as response:
                return json.load(response)
        except (OSError, ValueError) as error:  # timeouts, resets, HTTP errors, cut-off JSON
            if attempt == attempts:
                raise
            wait = PAUSE_SECONDS * 2 ** attempt
            print(f"  {error!r}; retrying in {wait}s ({attempt}/{attempts - 1})", file=sys.stderr)
            time.sleep(wait)


def live_rows():
    """Rows from every published term, oldest term first, plus names of terms that failed."""
    terms = [t for t in fetch("getClassScheduleTerms") if t.get("termDisplayControl") == "Y"]
    terms.sort(key=lambda t: t["termCode"])
    rows, failed = [], []
    for i, term in enumerate(terms):
        code = term["termCode"]
        if not (code.isdigit() and len(code) == 6):
            continue
        name = term.get("termName", code)
        if i:
            time.sleep(PAUSE_SECONDS)
        print(f"[{i + 1}/{len(terms)}] {name}…", file=sys.stderr, flush=True)
        try:
            term_rows = fetch("classSchedule/" + code)
        except (OSError, ValueError) as error:
            print(f"  Skipped {name}: {error!r}", file=sys.stderr)
            failed.append(name)
            continue
        print(f"  {len(term_rows)} sections", file=sys.stderr)
        rows.extend(term_rows)
    return rows, failed


def clean(value):
    return " ".join(str(value or "").split())


def split_name(full):
    """Split into (first, last, joined).

    The last word is the last name, extended left over surname particles, with
    any trailing suffix or "(maiden name)" kept on it. Everything before is the
    first name. joined is True when a particle or suffix was attached.
    """
    words = full.split(" ")
    if len(words) == 1:
        return "", words[0], False
    end = len(words)
    while end > 2 and (words[end - 1].lower() in SUFFIXES or words[end - 1].startswith("(")):
        end -= 1
    start = end - 1
    while start > 1 and words[start - 1].lower() in PARTICLES:
        start -= 1
    joined = start < end - 1 or end < len(words)
    return " ".join(words[:start]), " ".join(words[start:]), joined


def needs_check(first, last):
    """A multi-word first name may hide a double surname or middle name."""
    return not first or " " in first


def collect(rows):
    courses = {}     # code -> title (later terms win, so newest title is kept)
    professors = {}  # full name -> (first, last); identical names merge
    for row in rows:
        subject, number = clean(row.get("subjCode")), clean(row.get("courseNumbDisplay"))
        if subject and number:
            title = clean(row.get("courseTitle"))
            code = f"{subject} {number}"
            if title or code not in courses:
                courses[code] = title
        name = clean(row.get("pfaName"))
        if name and name.lower() not in {"staff", "tba", "to be announced"}:
            professors.setdefault(name, split_name(name))
    return courses, professors


def sql_text(value):
    return "'" + value.replace("'", "''") + "'"


def build_sql(courses, professors):
    lines = [
        "-- Generated by scripts/pcc_seed.py from PCC's public class schedule.",
        "-- Safe to re-run: existing courses and professors are skipped.",
        "begin;",
        "",
    ]
    if courses:
        values = ",\n".join(f"  ({sql_text(c)}, {sql_text(t)})" for c, t in sorted(courses.items()))
        lines += [
            "insert into public.courses (code, title) values",
            values,
            "on conflict (code) do nothing;",
            "",
        ]
    if professors:
        values = ",\n".join(f"  ({sql_text(f)}, {sql_text(l)})"
                            for f, l, _ in sorted(professors.values(), key=lambda p: (p[1], p[0])))
        lines += [
            "insert into public.professors (first_name, last_name)",
            "select v.first_name, v.last_name from (values",
            values,
            ") as v (first_name, last_name)",
            "where not exists (",
            "  select 1 from public.professors p",
            "  where p.first_name = v.first_name and p.last_name = v.last_name",
            ");",
            "",
        ]
    lines.append("commit;")
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--fixture", type=Path, help="JSON list of schedule rows to use instead of PCC")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT, help=f"output file (default {DEFAULT_OUT.name})")
    args = parser.parse_args()

    if args.fixture:
        rows, failed = json.loads(args.fixture.read_text()), []
    else:
        rows, failed = live_rows()
    courses, professors = collect(rows)
    args.out.write_text(build_sql(courses, professors))
    print(f"Wrote {args.out}: {len(courses)} courses, {len(professors)} professors.")

    joined = sorted(n for n, (_, _, j) in professors.items() if j)
    if joined:
        print("\nParticles or suffixes joined to the last name (glance over these):")
        for name in joined:
            first, last, _ = professors[name]
            print(f"  {name!r}: first={first!r}, last={last!r}")

    flagged = sorted(n for n, (f, l, _) in professors.items() if needs_check(f, l))
    if flagged:
        print("\nCheck how these names were split; a double surname or middle name"
              " may be in first_name (fix by hand in the SQL if wrong):")
        for name in flagged:
            first, last, _ = professors[name]
            print(f"  {name!r}: first={first!r}, last={last!r}")

    if failed:
        print(f"\nPCC didn't answer for: {', '.join(failed)}. Their professors and courses are missing;"
              " run the script again later (the SQL is safe to re-run).")


if __name__ == "__main__":
    main()
