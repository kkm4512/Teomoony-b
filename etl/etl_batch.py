"""Bounded batches for the large SQL Server ETL target lists."""
from concurrent.futures import FIRST_COMPLETED, wait


def pnu_targets(cur, source, params=(), limit=0):
    """Read unique PNU keys in order, applying the limit in SQL."""
    if limit < 0:
        raise ValueError("limit must be nonnegative")
    after = ""
    while True:
        size = min(limit, 1000) if limit else 1000
        cur.execute(f"""SELECT DISTINCT TOP (%s) x.pnu
                        FROM ({source}) AS x(pnu)
                        WHERE x.pnu > CAST(%s AS CHAR(19))
                        ORDER BY x.pnu""", (size, *params, after))
        rows = cur.fetchall()
        if not rows:
            return
        after = rows[-1][0]
        for (pnu,) in rows:
            yield pnu
        if len(rows) < size or limit == len(rows):
            return
        if limit:
            limit -= len(rows)


def bounded_map(executor, work, targets, window):
    """Run work over targets with at most `window` items in flight; yield results as they finish.

    2026-11-10: was batch-at-a-time (submit `window`, wait for all, submit next), so one slow call
    (API retry/backoff) left the other workers idle. Results now come in completion order, so a
    slow item never holds back the rest -- every caller's result carries its own key (pnu, url, ...).
    Stopping early (break / close) cancels what has not started yet, like executor.map.
    """
    targets = iter(targets)
    pending = set()
    try:
        while True:
            for target in targets:
                pending.add(executor.submit(work, target))
                if len(pending) >= window:
                    break
            if not pending:
                return
            done, pending = wait(pending, return_when=FIRST_COMPLETED)
            for f in done:
                yield f.result()
    finally:
        for f in pending:
            f.cancel()
