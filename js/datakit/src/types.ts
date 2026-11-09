// The dataset datakit's functions read and save (plan 0021).

import type { Characteristic, Missing, TableColumn, ValueLabels } from "@jbearak/dta-parser";

/**
 * A variable to save: dta-parser's `WriteVariable`, with the Parquet
 * types and fields. `saveParquet` and `writeParquet` take it as it is;
 * `saveDta` converts what a .dta file holds differently.
 */
export interface DatasetVariable {
  name: string;
  /**
   * Numbers, with `null` or a `Missing` for missing values; strings, with
   * `null` for a missing one (Parquet only); bigints; or a column as a
   * reader's `readColumns` returns it (`NumberColumn`, `StringColumn`,
   * `DictionaryColumn`, `BigIntColumn`), so what was read saves back as
   * it is. A Uint8Array among strings is binary.
   */
  values:
    | readonly (number | Missing | null)[]
    | readonly (string | Uint8Array)[]
    | readonly (string | Uint8Array | null)[]
    | Float64Array
    | readonly (bigint | null)[]
    | BigInt64Array
    | TableColumn;
  /**
   * With a Float64Array (or BigInt64Array) of values, each one's missing
   * code as `NumberColumn.missing` holds them (0 a value, 1 `.` or null, 2
   * to 27 `.a` to `.z`); none missing when absent.
   */
  missing?: Uint8Array;
  /**
   * The storage type: `"byte"`, `"int"`, `"long"`, `"float"`, `"double"`
   * (the default for numbers), strN or `"strL"`, as for .dta; and for
   * Parquet `"bool"` (0 and 1), `"int64"`, `"uint8"` to `"uint64"`,
   * `"date"` (days since 1970-01-01), `"timestamp"` (counts of `unit`
   * since 1970-01-01 00:00), `"time"`, `"decimal"`, `"string"`,
   * `"binary"` and `"categorical"`: the types a reader gives, so a
   * variable read saves back with its type.
   */
  type?:
    | "byte"
    | "int"
    | "long"
    | "float"
    | "double"
    | "strL"
    | "bool"
    | "int64"
    | "uint8"
    | "uint16"
    | "uint32"
    | "uint64"
    | "date"
    | "timestamp"
    | "time"
    | "decimal"
    | "string"
    | "binary"
    | "categorical"
    | (string & {});
  /** Parquet only: a timestamp's unit, `"s"`, `"ms"`, `"us"` (the default) or `"ns"`. */
  unit?: string;
  /**
   * Parquet only: a timestamp's time zone. With one, the values are
   * instants (adjusted to UTC) shown in that zone; without, clock times
   * with no zone.
   */
  timeZone?: string;
  /** A categorical's levels, when `values` holds level codes (0 the first level, null missing). */
  levels?: readonly string[];
  /** Whether a categorical's levels are ordered. */
  ordered?: boolean;
  /**
   * A categorical's levels and ordering, as a reader gives them. A factor
   * `readDta` restored (plan 0020's `dtaparser_factor`) also has the value
   * label set it came from, `labelSet`, and each level's code in it,
   * `codes`, so `saveDta` writes the same set and codes back.
   */
  categorical?: {
    readonly levels: readonly string[] | null;
    readonly ordered: boolean;
    readonly labelSet?: string;
    readonly codes?: readonly number[];
  };
  /** Display format; default the storage type's. */
  format?: string;
  label?: string;
  /** Name of a value label set in `Dataset.valueLabels`. */
  valueLabels?: string;
}

/** What `saveParquet` and `saveDta` take: the variables, in order, and the dataset's metadata. */
export interface Dataset {
  variables: readonly DatasetVariable[];
  /** Data label. */
  label?: string;
  /** Value label sets by name. */
  valueLabels?: Readonly<Record<string, ValueLabels>>;
  notes?: readonly string[];
  /** Characteristics, as a reader's `characteristics()` gives them. */
  characteristics?: readonly Characteristic[];
  /** Names of the variables the data is sorted by. */
  sortedBy?: readonly string[];
  /** .dta only: the file's timestamp, a Date or text written as given; default now. */
  timestamp?: Date | string;
}

/** A variable as the read functions return it: every field filled, `values` a reader's column. */
export interface ReadVariable extends DatasetVariable {
  type: string;
  format: string;
  label: string;
  /** The value label set's name; `""` when none (and for a restored factor, whose set is `categorical.labelSet`). */
  valueLabels: string;
  values: TableColumn;
  unit?: "day" | "s" | "ms" | "us" | "ns";
  categorical?: { levels: string[] | null; ordered: boolean; labelSet?: string; codes?: number[] };
}

/** What the read functions return: a whole table, every field filled. */
export interface ReadDataset extends Dataset {
  variables: ReadVariable[];
  label: string;
  notes: string[];
  /** Every value label set the file has, used or not (a restored factor's set aside). */
  valueLabels: Record<string, ValueLabels>;
  characteristics: Characteristic[];
  sortedBy: string[];
}
