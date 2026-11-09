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
   * Numbers, with `null`, a `Missing`, `NA` or a `taggedNa` for missing
   * values (in a Float64Array, `NA` and tagged NaNs); strings, with
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
   * With a BigInt64Array of values, 1 where a value is null, else 0; none
   * null when absent. A Float64Array holds its missing values itself.
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
   * A categorical's levels and ordering, as a reader gives them. A
   * variable `readDta` restored (marked `dtaparser_factor`, plan 0020, or
   * `dtaparser_categorical`, plan 0023) also has the value label set it
   * came from, `labelSet`, and each level's code in it, `codes`, so
   * `saveDta` writes the same set and codes back. `saveDta` takes codes
   * that increase with the levels; a code given twice, or out of order,
   * is an error.
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
  /**
   * The value label set's name; `""` when none, and for a restored
   * categorical whose set labels no `.a` to `.z` (its set is
   * `categorical.labelSet`).
   */
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
  /**
   * Every value label set the file has, used or not, except a restored
   * categorical's set that no variable read names.
   */
  valueLabels: Record<string, ValueLabels>;
  characteristics: Characteristic[];
  sortedBy: string[];
}
