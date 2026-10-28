/* Write one small .dta fixture of a given release with ReadStat's writer,
 * from data made here. Built and run by compat/make_legacy_fixtures.sh.
 *
 *   write_fixture <release> <out.dta>
 *
 * Releases before 113 have only one missing value per type, so the
 * extended missing values .a and .z are written only from 113. */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include "readstat.h"

static ssize_t write_bytes(const void *data, size_t len, void *ctx) {
    return write(*(int *)ctx, data, len);
}

#define CHECK(call) do { readstat_error_t e = (call); if (e != READSTAT_OK) { \
    fprintf(stderr, "%s: %s\n", #call, readstat_error_message(e)); return 1; } } while (0)

int main(int argc, char **argv) {
    if (argc != 3) { fprintf(stderr, "usage: write_fixture <release> <out.dta>\n"); return 2; }
    int release = atoi(argv[1]);
    int extended = release >= 113;
    int fd = open(argv[2], O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) { perror(argv[2]); return 1; }

    readstat_writer_t *w = readstat_writer_init();
    CHECK(readstat_set_data_writer(w, write_bytes));
    CHECK(readstat_writer_set_file_label(w, "ReadStat fixture"));
    CHECK(readstat_writer_set_file_format_version(w, (uint8_t) release));

    readstat_label_set_t *yesno = readstat_add_label_set(w, READSTAT_TYPE_INT32, "yesno");
    readstat_label_int32_value(yesno, 0, "No");
    readstat_label_int32_value(yesno, 1, "Yes");
    readstat_label_int32_value(yesno, -5, "Refused");

    readstat_variable_t *b = readstat_add_variable(w, "b", READSTAT_TYPE_INT8, 0);
    readstat_variable_set_label(b, "A byte");
    readstat_variable_set_label_set(b, yesno);
    readstat_variable_t *i = readstat_add_variable(w, "i", READSTAT_TYPE_INT16, 0);
    readstat_variable_t *l = readstat_add_variable(w, "l", READSTAT_TYPE_INT32, 0);
    readstat_variable_set_label(l, "A long");
    readstat_variable_t *f = readstat_add_variable(w, "f", READSTAT_TYPE_FLOAT, 0);
    readstat_variable_t *d = readstat_add_variable(w, "d", READSTAT_TYPE_DOUBLE, 0);
    readstat_variable_t *s = readstat_add_variable(w, "s", READSTAT_TYPE_STRING, 8);
    readstat_variable_set_label(s, "A string");

    CHECK(readstat_begin_writing_dta(w, &fd, 5));
    const int8_t bs[] = {1, 0, -5, 100, 1};
    const int16_t is[] = {1000, -32000, 0, 127, 32000};  /* 127 is the byte sentinel */
    const int32_t ls[] = {1, -2000000000, 2000000000, 0, 32767};  /* the int sentinel */
    const float fs[] = {1.5f, -2.25f, 0.0f, 1e30f, 3.0f};
    const double ds[] = {1.0 / 3.0, -1e300, 0.0, 2.5, 123456789.125};
    const char *ss[] = {"abc", "", "eight ch", "x y", "z"};
    for (int r = 0; r < 5; r++) {
        CHECK(readstat_begin_row(w));
        CHECK(readstat_insert_int8_value(w, b, bs[r]));
        if (r == 2) CHECK(readstat_insert_missing_value(w, i));
        else CHECK(readstat_insert_int16_value(w, i, is[r]));
        if (r == 3 && extended) CHECK(readstat_insert_tagged_missing_value(w, l, 'a'));
        else if (r == 3) CHECK(readstat_insert_missing_value(w, l));
        else CHECK(readstat_insert_int32_value(w, l, ls[r]));
        if (r == 1) CHECK(readstat_insert_missing_value(w, f));
        else CHECK(readstat_insert_float_value(w, f, fs[r]));
        if (r == 4 && extended) CHECK(readstat_insert_tagged_missing_value(w, d, 'z'));
        else if (r == 4) CHECK(readstat_insert_missing_value(w, d));
        else CHECK(readstat_insert_double_value(w, d, ds[r]));
        CHECK(readstat_insert_string_value(w, s, ss[r]));
        CHECK(readstat_end_row(w));
    }
    CHECK(readstat_end_writing(w));
    readstat_writer_free(w);
    close(fd);
    return 0;
}
