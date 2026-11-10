"""Bounded batches for the large SQL Server ETL target lists."""
from itertools import islice


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
    """Keep at most one window of ordered work submitted at a time."""
    targets = iter(targets)
    while batch := list(islice(targets, window)):
        yield from executor.map(work, batch)
