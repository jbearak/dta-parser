"""Value, shape, order and summary checks for the private float policy screen."""
from collections import Counter
from decimal import Decimal, InvalidOperation
import itertools
import math
import statistics

PANELS = {
    'density': ('random_half', 'clustered_half', 'all_tags'),
    'pattern': ('dense_prefix256', 'dense_suffix256', 'alternating64'),
    'ordinary': ('none', 'sparse'),
}
LAYOUTS = ('plain', 'retained')
OPERATIONS = ('pair_less', 'pair_equal')
REPRESENTATIONS = ('compact', 'typed_double')
FIELDS = ('pattern', 'layout', 'operation', 'representation')
HASHES = ('result_hash', 'input_hash', 'y_hash', 'metadata_x', 'metadata_y',
          'rank_x_hash', 'rank_y_hash')
STATE_PREFIXES = ('compact', 'materialized', 'y_compact', 'y_materialized',
                  'retained', 'y_retained', 'chunks', 'y_chunks')
STATES = tuple(k + '_before' for k in STATE_PREFIXES)
RESULT_FIELDS = HASHES + STATES + ('x_missing', 'y_missing', 'pair_missing')
VALUE_FIELDS = ('result_hash', 'input_hash', 'y_hash', 'rank_x_hash',
                'rank_y_hash', 'x_missing', 'y_missing', 'pair_missing')


def require(ok, message):
    if not ok:
        raise RuntimeError(message)


def integer(value):
    try:
        number = Decimal(str(value))
    except InvalidOperation:
        raise RuntimeError('Invalid integer')
    require(number.is_finite() and number >= 0 and
            number == number.to_integral_value(), 'Invalid integer')
    return int(number)


def cases(panel):
    return set(itertools.product(PANELS[panel], LAYOUTS, OPERATIONS, REPRESENTATIONS))


def patterns(number, panel):
    choices = PANELS[panel]
    if len(choices) == 3:
        return tuple(itertools.permutations(choices))[(number - 1) % 6]
    return choices if number % 2 else tuple(reversed(choices))


def order(number, panel):
    operations = OPERATIONS if number % 2 else tuple(reversed(OPERATIONS))
    result = []
    for pp, pattern in enumerate(patterns(number, panel), 1):
        layouts = LAYOUTS if (number + PANELS[panel].index(pattern) + 1) % 2 else tuple(reversed(LAYOUTS))
        for lp, layout in enumerate(layouts, 1):
            for op, operation in enumerate(operations, 1):
                case = PANELS[panel].index(pattern) * 4 + LAYOUTS.index(layout) * 2 + OPERATIONS.index(operation) + 1
                reps = REPRESENTATIONS if (number + case) % 2 else tuple(reversed(REPRESENTATIONS))
                for rp, representation in enumerate(reps, 1):
                    result.append((pattern, layout, operation, representation, pp, lp, op, rp))
    return result


def missing_counts(pattern):
    if pattern == 'none':
        return 0, 0, 0
    if pattern == 'sparse':
        x = set(range(13, 1_000_001, 997))
        y = set(range(19, 1_000_001, 991))
        return len(x), len(y), len(x | y)
    if pattern == 'random_half':
        # Marginals are exact; joint count is additionally bound by the full
        # rank hashes, the independent R oracle, and cross-layout equality.
        return 500_000, 500_000, None
    value = {'clustered_half': 500_000, 'all_tags': 1_000_000,
             'dense_prefix256': 256, 'dense_suffix256': 256,
             'alternating64': 500_032}[pattern]
    return value, value, value


def validate_round(rows, number, phase, panel):
    expected = cases(panel)
    require(Counter(tuple(row[k] for k in FIELDS) for row in rows) ==
            Counter({key: 1 for key in expected}), 'Incomplete or repeated case matrix')
    require([(r['pattern'], r['layout'], r['operation'], r['representation'],
              integer(r['pattern_position']), integer(r['layout_position']),
              integer(r['operation_position']), integer(r['position'])) for r in rows] ==
            order(number, panel), 'Execution order changed')
    for row in rows:
        require(row['panel'] == panel and integer(row['round']) == number and
                row['threads'] == '1' and integer(row['rows']) == 1_000_000 and
                integer(row['repetitions']) > 0, 'Wrong panel/round/threads/shape/repetitions')
        require(row['phase'] == phase, 'Wrong worker phase')
        if phase == 'qualify':
            require(integer(row['repetitions']) == 1, 'Qualification repeated a call')
        for metric in ('cpu', 'wall'):
            value = float(row[metric])
            require(math.isfinite(value) and (value > 0 if phase == 'measure' else value == 0),
                    'Invalid timing interval')
        xm, ym, joint = missing_counts(row['pattern'])
        require(integer(row['x_missing']) == xm and integer(row['y_missing']) == ym,
                'Wrong marginal missing counts')
        pair = integer(row['pair_missing'])
        require(500_000 <= pair <= 1_000_000 if joint is None else pair == joint,
                'Wrong joint missing count')
        for prefix in STATE_PREFIXES:
            require(row[prefix + '_before'] == row[prefix + '_after'], 'Source state changed')
        compact = str(row['representation'] == 'compact').upper()
        require(row['compact_before'] == row['y_compact_before'] == compact and
                row['materialized_before'] == row['y_materialized_before'] == 'FALSE',
                'Wrong source representation')
        retained = int(row['representation'] == 'compact' and row['layout'] == 'retained')
        require(integer(row['retained_before']) == integer(row['y_retained_before']) == retained,
                'Wrong retained payload state')
        require(integer(row['chunks_before']) == (123 if retained else 0) and
                integer(row['y_chunks_before']) == (62 if retained else 0), 'Wrong retained span geometry')
        require(row['native_qualified'] == 'TRUE', 'Native path not qualified')
        for field in HASHES:
            require(len(row[field]) == 64 and set(row[field]) <= set('0123456789abcdef'),
                    'Malformed full hash')


def validate_all(rows, rounds, phase, panel):
    expected = cases(panel)
    require(len(rows) == 2 * rounds * len(expected), 'Observation count')
    rebuilt = []
    for number in range(1, rounds + 1):
        for variant in ('baseline', 'candidate') if number % 2 else ('candidate', 'baseline'):
            group = [r for r in rows if r['variant'] == variant and integer(r['round']) == number]
            validate_round(group, number, phase, panel)
            rebuilt.extend(group)
    require(rebuilt == rows, 'Build execution order changed')
    for case in expected:
        selected = [r for r in rows if tuple(r[k] for k in FIELDS) == case]
        require(len({tuple(r[k] for k in RESULT_FIELDS) for r in selected}) == 1,
                'Source/result/metadata changed across builds or rounds')
        if phase == 'measure':
            for variant in ('baseline', 'candidate'):
                for position in ('position', 'layout_position'):
                    require(Counter(integer(r[position]) for r in selected if r['variant'] == variant) ==
                            Counter({1: rounds // 2, 2: rounds // 2}), 'Unbalanced representation/layout order')
    for pattern, operation in itertools.product(PANELS[panel], OPERATIONS):
        selected = [r for r in rows if r['pattern'] == pattern and r['operation'] == operation]
        require(len({tuple(r[k] for k in VALUE_FIELDS) for r in selected}) == 1,
                'Equivalent representations/layouts disagree')
    if phase == 'measure':
        possible = list(itertools.permutations(PANELS[panel]))
        for variant in ('baseline', 'candidate'):
            observed = []
            for number in range(1, rounds + 1):
                group = [r for r in rows if r['variant'] == variant and integer(r['round']) == number]
                observed.append(tuple(dict.fromkeys(r['pattern'] for r in group)))
            require(Counter(observed) == Counter({p: rounds // len(possible) for p in possible}),
                    'Unbalanced pattern permutations')


def summarize(rows, panel):
    result = []
    for pattern, layout, operation in itertools.product(PANELS[panel], LAYOUTS, OPERATIONS):
        record = dict(panel=panel, pattern=pattern, layout=layout, operation=operation)
        selected = {variant: {rep: sorted(
            [r for r in rows if r['variant'] == variant and r['pattern'] == pattern and
             r['layout'] == layout and r['operation'] == operation and r['representation'] == rep],
            key=lambda r: integer(r['round'])) for rep in REPRESENTATIONS}
            for variant in ('baseline', 'candidate')}
        for variant in selected:
            for rep in REPRESENTATIONS:
                for metric in ('cpu', 'wall'):
                    record[f'{variant}_{rep}_{metric}'] = statistics.median(
                        float(r[metric]) / integer(r['repetitions']) for r in selected[variant][rep])
            record[variant + '_compact_typed_cpu'] = record[variant + '_compact_cpu'] / record[variant + '_typed_double_cpu']
        for rep in REPRESENTATIONS:
            for metric in ('cpu', 'wall'):
                record[f'{rep}_{metric}_speedup'] = record[f'baseline_{rep}_{metric}'] / record[f'candidate_{rep}_{metric}']
                record[f'{rep}_{metric}_paired_median_speedup'] = statistics.median(
                    (float(b[metric]) / integer(b['repetitions'])) / (float(c[metric]) / integer(c['repetitions']))
                    for b, c in zip(selected['baseline'][rep], selected['candidate'][rep]))
        result.append(record)
    return result
