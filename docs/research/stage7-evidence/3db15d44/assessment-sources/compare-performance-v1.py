"""Compare two independently assessed Stage7 fixed-workload matrices."""
import argparse
import csv
import hashlib
import json
from pathlib import Path


def require(value, message):
    if not value:
        raise RuntimeError(message)


def identity(path):
    return dict(path=str(path), resolved=str(path.resolve(strict=True)),
                bytes=path.stat().st_size, mode=oct(path.stat().st_mode & 0o777),
                sha256=hashlib.sha256(path.read_bytes()).hexdigest())


def read(path, expected):
    bound = identity(path)
    require(bound['sha256'] == expected, 'Assessment identity differs')
    result = json.loads(path.read_text())
    require(identity(path) == bound, 'Assessment changed while reading')
    require(identity(Path(result['receipt']['path'])) == result['receipt'], 'Run receipt changed')
    require(identity(Path(result['manifest']['path'])) == result['manifest'], 'Run manifest changed')
    return bound, result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('predecessor', type=Path)
    parser.add_argument('predecessor_digest')
    parser.add_argument('candidate', type=Path)
    parser.add_argument('candidate_digest')
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    before_identity, before = read(args.predecessor, args.predecessor_digest)
    after_identity, after = read(args.candidate, args.candidate_digest)
    require(before['source'] == '4d07d656dc95cd2cf5fae12c1dc08d6fae4f8d2c', 'Wrong predecessor')
    require(after['source'] != before['source'], 'Candidate must be distinct')
    require(before['series'] == 108 and after['series'] == 54, 'Wrong matrix sizes')
    key_fields = ['rows', 'columns', 'groups', 'workload']
    key = lambda row: tuple(row[field] for field in key_fields)
    candidates = {key(row): row for row in after['operation_rows']}
    require(len(candidates) == 54 and all(row['route'] == 'public' for row in candidates.values()),
            'Invalid candidate routes/shapes')
    comparisons = []
    for row in before['operation_rows']:
        new = candidates[key(row)]
        result = {field: row[field] for field in key_fields}
        result['reference_route'] = row['route']
        for metric in row:
            if metric in key_fields + ['route', 'values_metadata_groups_source']:
                continue
            old_value, new_value = float(row[metric]), float(new[metric])
            result['before_' + metric] = old_value
            result['after_' + metric] = new_value
            result['delta_' + metric] = new_value - old_value
        result['median_ratio'] = result['after_median_ms'] / result['before_median_ms']
        result['investigation_flag'] = result['median_ratio'] > 1.1 and result['delta_median_ms'] > 1
        comparisons.append(result)
    require(len(comparisons) == 108 and
            {row['reference_route'] for row in comparisons} == {'public', 'predecessor_safe_reference'},
            'Incomplete comparisons')
    args.output.mkdir(parents=True, exist_ok=False)
    csv_path = args.output / 'comparisons.csv'
    with csv_path.open('x') as stream:
        writer = csv.DictWriter(stream, fieldnames=list(comparisons[0]))
        writer.writeheader()
        writer.writerows(comparisons)
    result = dict(predecessor=before_identity, candidate=after_identity,
                  predecessor_source=before['source'], candidate_source=after['source'],
                  comparison_source=identity(Path(__file__).resolve()),
                  comparisons=identity(csv_path), pairs=len(comparisons),
                  raw_samples=before['raw_samples'] + after['raw_samples'],
                  flags=[row for row in comparisons if row['investigation_flag']],
                  scope='Candidate public versus predecessor public and fixed safe-reference routes. '
                        'Single quiet grids with seven GC-inclusive samples per series; flags above 10% and 1ms require investigation of repeatability. '
                        'Legacy public nesting lacks the foreign-write guarantee. First/warm R and native observations overlap and are not summed. '
                        'No independent nested-memory or stage-wide acceptance from this comparison.')
    with (args.output / 'result.json').open('x') as stream:
        json.dump(result, stream, indent=2)
        stream.write('\n')
    print(json.dumps(dict(pairs=len(comparisons), investigation_flags=len(result['flags']),
                         source=after['source'], result=str(args.output / 'result.json'))))


if __name__ == '__main__':
    main()
