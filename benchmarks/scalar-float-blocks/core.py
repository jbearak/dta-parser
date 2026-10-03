"""Matrix, value, native-entry and ordering checks for scalar float blocks."""
from collections import Counter
from decimal import Decimal, InvalidOperation
import itertools
import math
import statistics

PATTERNS = ('none', 'sparse', 'random_half', 'clustered_half',
            'prefix256', 'suffix256', 'all_tags')
OPERATIONS = ('add', 'subtract', 'multiply', 'divide')
FIELDS = ('pattern', 'operation', 'representation')
HASHES = ('input_hash', 'rank_hash', 'result_hash', 'missing_hash',
          'metadata_hash', 'result_metadata_hash')
STATE_NAMES = ('compact', 'materialized', 'retained', 'chunks')
RESULT_FIELDS = HASHES + ('input_missing', 'result_missing', 'result_storage') + tuple(
    x + '_before' for x in STATE_NAMES)
COUNTS = dict(none=0, sparse=1003, random_half=500000, clustered_half=500000,
              prefix256=256, suffix256=256, all_tags=1000000)


def require(ok, message):
    if not ok:
        raise RuntimeError(message)


def integer(value):
    try:
        n = Decimal(str(value))
    except InvalidOperation:
        raise RuntimeError('Invalid integer')
    require(n.is_finite() and n >= 0 and n == n.to_integral_value(), 'Invalid integer')
    return int(n)


def representations(pattern):
    return ('compact', 'typed_double', 'ordinary') if pattern == 'none' else ('compact', 'typed_double')


def cases():
    return {(p, op, rep) for p in PATTERNS for op in OPERATIONS for rep in representations(p)}


def order(number):
    offset = (number - 1) % len(PATTERNS)
    patterns = PATTERNS[offset:] + PATTERNS[:offset]
    if number % 2 == 0:
        patterns = tuple(reversed(patterns))
    operations = OPERATIONS if number % 2 else tuple(reversed(OPERATIONS))
    result = []
    for pp, pattern in enumerate(patterns, 1):
        for op, operation in enumerate(operations, 1):
            reps = representations(pattern)
            if len(reps) == 3:
                reps = tuple(itertools.permutations(reps))[(number - 1 + OPERATIONS.index(operation)) % 6]
            elif (number + PATTERNS.index(pattern) + OPERATIONS.index(operation)) % 2 == 0:
                reps = tuple(reversed(reps))
            for rp, representation in enumerate(reps, 1):
                result.append((pattern, operation, representation, pp, op, rp))
    return result


def validate_round(rows, number, phase):
    require(Counter(tuple(r[k] for k in FIELDS) for r in rows) ==
            Counter({case: 1 for case in cases()}), 'Incomplete or repeated matrix')
    require([(r['pattern'], r['operation'], r['representation'], integer(r['pattern_position']),
              integer(r['operation_position']), integer(r['position'])) for r in rows] == order(number),
            'Execution order changed')
    for r in rows:
        require(r['phase'] == phase and integer(r['round']) == number and
                integer(r['rows']) == 1000000 and integer(r['threads']) == 1, 'Wrong phase/shape')
        reps = integer(r['repetitions'])
        require(reps > 0 and (phase != 'qualify' or reps == 1), 'Invalid repetition count')
        for metric in ('cpu', 'wall'):
            value = float(r[metric])
            require(math.isfinite(value) and (value > 0 if phase == 'measure' else value == 0),
                    'Invalid timing interval')
        expected_entries = 0 if r['representation'] == 'ordinary' else reps
        require(integer(r['native_calls']) == expected_entries and
                integer(r['qualification_calls']) == (0 if expected_entries == 0 else 1),
                'Native path entry count changed')
        require(integer(r['input_missing']) == integer(r['result_missing']) == COUNTS[r['pattern']],
                'Missing count changed')
        require(r['result_storage'] == {'compact': 'float', 'typed_double': 'double', 'ordinary': ''}[r['representation']],
                'Unexpected result storage')
        for prefix in STATE_NAMES:
            require(r[prefix + '_before'] == r[prefix + '_after'], 'Source state changed')
        require(r['compact_before'] == str(r['representation'] == 'compact').upper() and
                r['materialized_before'] == 'FALSE' and integer(r['retained_before']) == 0 and
                integer(r['chunks_before']) == 0, 'Unexpected source representation')
        for field in HASHES:
            require(len(r[field]) == 64 and set(r[field]) <= set('0123456789abcdef'), 'Malformed full hash')


def validate_all(rows, rounds, phase):
    require(len(rows) == 2 * rounds * len(cases()), 'Observation count')
    rebuilt = []
    for number in range(1, rounds + 1):
        for variant in ('baseline', 'candidate') if number % 2 else ('candidate', 'baseline'):
            group = [r for r in rows if r['variant'] == variant and integer(r['round']) == number]
            validate_round(group, number, phase)
            rebuilt.extend(group)
    require(rebuilt == rows, 'Build order changed')
    for case in cases():
        selected = [r for r in rows if tuple(r[k] for k in FIELDS) == case]
        require(len({tuple(r[k] for k in RESULT_FIELDS) for r in selected}) == 1,
                'Source/result/metadata differs across builds or rounds')
        if phase == 'measure':
            width = len(representations(case[0]))
            for variant in ('baseline', 'candidate'):
                require(Counter(integer(r['position']) for r in selected if r['variant'] == variant) ==
                        Counter({p: rounds // width for p in range(1, width + 1)}), 'Unbalanced representations')
    for pattern in PATTERNS:
        selected = [r for r in rows if r['pattern'] == pattern]
        require(len({(r['input_hash'], r['rank_hash'], r['input_missing']) for r in selected}) == 1,
                'Equivalent inputs differ across representations/operations')
    # Output values intentionally differ by storage width. Only same-storage
    # results are compared across builds. Bare and typed no-missing results match.
    for operation in OPERATIONS:
        selected = [r for r in rows if r['pattern'] == 'none' and r['operation'] == operation and
                    r['representation'] != 'compact']
        require(len({(r['result_hash'], r['missing_hash']) for r in selected}) == 1,
                'Bare and typed binary64 results differ')


def summarize(rows):
    results = []
    for pattern, operation in itertools.product(PATTERNS, OPERATIONS):
        row = dict(pattern=pattern, operation=operation)
        groups = {(v, rep): sorted([r for r in rows if r['pattern'] == pattern and
            r['operation'] == operation and r['variant'] == v and r['representation'] == rep],
            key=lambda r: integer(r['round'])) for v in ('baseline', 'candidate') for rep in representations(pattern)}
        for (variant, rep), group in groups.items():
            for metric in ('cpu', 'wall'):
                row[f'{variant}_{rep}_{metric}'] = statistics.median(float(r[metric]) / integer(r['repetitions']) for r in group)
        for rep in representations(pattern):
            for metric in ('cpu', 'wall'):
                row[f'{rep}_{metric}_speedup'] = row[f'baseline_{rep}_{metric}'] / row[f'candidate_{rep}_{metric}']
                row[f'{rep}_{metric}_paired_speedup'] = statistics.median(
                    (float(b[metric]) / integer(b['repetitions'])) / (float(c[metric]) / integer(c['repetitions']))
                    for b, c in zip(groups['baseline', rep], groups['candidate', rep]))
        for variant in ('baseline', 'candidate'):
            row[f'{variant}_compact_typed_cpu'] = row[f'{variant}_compact_cpu'] / row[f'{variant}_typed_double_cpu']
            if pattern == 'none':
                row[f'{variant}_compact_ordinary_cpu'] = row[f'{variant}_compact_cpu'] / row[f'{variant}_ordinary_cpu']
        results.append(row)
    return results
