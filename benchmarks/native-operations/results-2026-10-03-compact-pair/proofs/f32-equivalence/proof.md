# Standalone multiplication equivalence qualification

This experiment changes no package source. It checks a proposed implementation of the existing binary64 arithmetic and storage contract. It is not permission to change that contract, an integrated kernel test, an exhaustive enumeration of all float pairs, or a performance measurement.

## Exact mathematical argument

Admission would be restricted to multiplication of two compact physical byte, int16, or binary32 columns, with at least one binary32 input and an initially binary32 output. It excludes long integers, binary64 inputs, scalar recycling, and temporal conversion.

A finite binary32 value has at most 24 significand bits. Multiplying two such values therefore produces an exact value with at most 48 significand bits. A physical int16 needs at most 16, giving at most 40 bits when multiplied by a binary32 value. Binary64 has 53 significand bits. The smallest nonzero float product is 2^-298 and the largest magnitude is less than 2^256, both inside binary64's normal exponent range. Thus the established binary64 product is exact for every admitted finite pair, including physical signed minima, subnormals, and modern noncanonical high finite imports.

Correctly rounding that exact product to binary32 gives the same bits as correctly rounded binary32 multiplication of the original inputs. The diagnostic checks round-to-nearest, downward, upward, and toward-zero independently. Signed zero and subnormal rounding are compared bit for bit.

Storage promotion remains based on the exact binary64 product. Let L be the largest observed Stata binary32 magnitude, encoded by 0x7effffff. L is exactly representable. For any supported rounding mode, a rounded magnitude strictly below L proves that the exact magnitude is below L; a rounded magnitude strictly above L proves that the exact magnitude is above L. Equality proves neither. Every equality case must run the existing exact binary64 fit calculation. If any lane requires double storage, every observed output must be recomputed from its original inputs in binary64, rather than widening earlier rounded float results. The standalone whole-column model checks this distinction, resetting provisional missing counts and recomputing earlier precision-sensitive lanes when a late value forces promotion.

The argument applies only to finite observed input products. Source-format missing encodings, NaNs, and either observed infinity all produce system missing for multiplication under the existing contract. The probe uses exact extracted current source classifiers as its reference, checks an independent source-width classifier, masks invalid operands before the proposed product, and compares missing unions and system-missing output bits. It does not propose changing missing interpretation or narrowing import acceptance.

## Results

The optimized and undefined-behavior-sanitized standalone binaries each passed 36,914,944 scalar comparisons with identical checksums and zero mismatches. Each rounding mode contributed 9,228,736 comparisons. The fixture covers every physical int16 value against selected adversarial floats, every physical byte against the complete endpoint fixture, all 27 modern missing tags and their immediate raw neighbors, both signs of zero and infinities, NaNs, subnormals, float maxima, immediate neighbors around L/integer, and deterministic random raw float pairs. Both legacy and modern classifications are included independently for each operand.

There were 366,468 rounded-equality cases: 225,164 exact products above L, 134,168 below L, and 7,136 exactly at L. Another 12,538,521 strict rounded-promotion cases independently required binary64 storage. Nineteen whole-column cases checked full recomputation and missing unions across intersected 3-row and 4-row chunks. Toward-zero rounding has no below-L equality witness because that category is mathematically impossible; per-mode evidence records its zero count explicitly.

Concrete round-to-nearest witnesses show why equality must fall back:

- 11 × binary32(0x7d3a2e8b) rounds to L, but its exact product is binary64(0x47dfffffe4000000), above L. It requires double storage.
- 19 × binary32(0x7cd79435) also rounds to L, but its exact product is binary64(0x47dfffffde000000), below L. It retains float storage.
- 0.5 × binary32(0x7f7fffff) equals L exactly: binary64(0x47dfffffe0000000). The modern imported high finite input remains observed and the result retains float storage.

The private `exact-witnesses.py` supplement verifies every recorded witness using exact rational arithmetic, independently of the C floating calculations. `receipt.json` binds the exact extracted classifier text and source hash, compiler binary/version, complete command lines, probe and controller hashes before and after execution, result hashes, and the clean package head. `initial-v1` preserves the earlier diagnostic before per-mode recording and explicit fenv checks were added.

## Limits and next review

This demonstrates output-value, storage, promotion, and missing-count equivalence for the sampled implementation model, supported by the finite-domain proof. It does not validate a production dispatch implementation, read-claim lifetimes, R allocation/reentrancy, retained chunk ownership, cross-platform compiler behavior, floating exception flags, or speed. Those still require independent source review, existing integration regressions, clean builds on supported targets, and a controlled benchmark after any production edit is separately approved. The production branch remains unchanged by this experiment.
