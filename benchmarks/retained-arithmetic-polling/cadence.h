/* Independent endpoint model for the actual-header structural probe.
   The model packs the original complete span intersections. It does not
   reproduce the candidate's budget-subtraction spelling. */
typedef struct {
    size_t span_calls, interrupt_calls, maximum_gap;
    uint64_t span_trace, poll_trace;
} expected_schedule;

static void schedule_word(uint64_t *hash, uint64_t value) {
    for (unsigned byte = 0; byte < 8; byte++) {
        *hash ^= value & 255U;
        *hash *= UINT64_C(1099511628211);
        value >>= 8;
    }
}

static size_t earlier(size_t a, size_t b) { return a < b ? a : b; }

static expected_schedule model_complete_spans(
    size_t length, size_t long_chunk, size_t float_chunk, int reverse
) {
    expected_schedule model = {
        0, 1, 0, UINT64_C(14695981039346656037),
        UINT64_C(14695981039346656037)
    };
    schedule_word(&model.poll_trace, 0); /* initial check, before lookup */
    const size_t first_chunk = reverse ? float_chunk : long_chunk;
    const size_t second_chunk = reverse ? long_chunk : float_chunk;
    const int first_kind = reverse ? NUMERIC_FLOAT : NUMERIC_LONG;
    const int second_kind = reverse ? NUMERIC_LONG : NUMERIC_FLOAT;
    size_t last_poll = 0;
    for (size_t begin = 0; begin < length;) {
        size_t limit = earlier(length, begin + 16384);
        size_t first_boundary = first_chunk
            ? (begin / first_chunk + 1) * first_chunk : length;
        size_t first_end = earlier(limit, first_boundary);
        size_t second_boundary = second_chunk
            ? (begin / second_chunk + 1) * second_chunk : length;
        size_t end = earlier(first_end, second_boundary);
        if (end <= begin || end - begin > 16384) abort();

        schedule_word(&model.span_trace, (uint64_t) first_kind);
        schedule_word(&model.span_trace, begin);
        schedule_word(&model.span_trace, limit - begin);
        schedule_word(&model.span_trace, first_end - begin);
        schedule_word(&model.span_trace, (uint64_t) second_kind);
        schedule_word(&model.span_trace, begin);
        schedule_word(&model.span_trace, first_end - begin);
        schedule_word(&model.span_trace, end - begin);
        model.span_calls += 2;

        /* Absolute endpoints independently express the completed-row bound.
           Fixture sizes are bounded to one million, so this sum cannot wrap. */
        if (end > last_poll + 16384) {
            schedule_word(&model.poll_trace, begin);
            model.interrupt_calls++;
            last_poll = begin;
        }
        if (end - last_poll > model.maximum_gap)
            model.maximum_gap = end - last_poll;
        begin = end;
    }
    return model;
}

/* The controller inserts this at the long/float completed-span seam, just
   before start += count. Span acquisition alone no longer implies completed
   work, because the candidate may now poll after acquiring the pointers. */
static void probe_complete_span(size_t start, size_t count) {
    if (start != completed_rows || count == 0 || count > 16384) abort();
    completed_rows += count;
    size_t gap = completed_rows - last_poll_row;
    if (gap > max_poll_gap) max_poll_gap = gap;
}

/* The adapted R_CheckUserInterrupt mock will hash completed_rows into a
   distinct poll_trace, then update last_poll_row. Its call count, trace,
   maximum gap and complete-span trace/count must equal model_complete_spans.
   Keep value/source/missing failures separate from these structural failures.
   Baseline and split-budget v1 should be red; whole-span v2 should be green.
   Reuse the unchanged 18 semantic/geometry cases and emit both expected and
   actual fields, including actual maximum processed-row gap. */
