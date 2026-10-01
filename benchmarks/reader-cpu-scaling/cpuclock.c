/* Same-process Stata read clocks. Build with the unmodified official SPI 3.0. */
#include "stplugin.h"
#include <string.h>
#include <sys/resource.h>
#include <time.h>

static struct rusage beginning_usage;
static struct timespec beginning_wall;
static int armed = 0;

static double seconds(struct timeval value) {
    return (double) value.tv_sec + (double) value.tv_usec / 1000000.0;
}

STDLL stata_call(int argc, char *argv[]) {
    struct rusage usage;
    struct timespec wall;
    int rc;
    if (argc != 1 || (strcmp(argv[0], "start") && strcmp(argv[0], "stop")))
        return 198;
    /* Match the snapshot ordering at both ends; publishing scalars is outside
       the stop snapshot. Empty intervals measure the remaining call overhead. */
    if (clock_gettime(CLOCK_MONOTONIC, &wall) || getrusage(RUSAGE_SELF, &usage))
        return 912;
    if (!strcmp(argv[0], "start")) {
        if (armed) return 198;
        beginning_usage = usage;
        beginning_wall = wall;
        armed = 1;
        return 0;
    }
    if (!armed) return 198;
    armed = 0;
    double elapsed = (double) (wall.tv_sec - beginning_wall.tv_sec) +
        (double) (wall.tv_nsec - beginning_wall.tv_nsec) / 1000000000.0;
    if ((rc = SF_scal_save("_dta_cpu_wall", elapsed))) return rc;
    if ((rc = SF_scal_save("_dta_cpu_user", seconds(usage.ru_utime) -
                          seconds(beginning_usage.ru_utime)))) return rc;
    return SF_scal_save("_dta_cpu_system", seconds(usage.ru_stime) -
                        seconds(beginning_usage.ru_stime));
}
