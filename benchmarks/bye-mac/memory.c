#include <libproc.h>
#include <sys/resource.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>
#include <mach/mach_time.h>

// Physical footprint and resident size are different accounting views.
// Never add Metal allocation logs to either figure.
int main(int argc, char **argv) {
    if (argc != 3) return 64;
    pid_t host = atoi(argv[1]), runtime = atoi(argv[2]);
    mach_timebase_info_data_t base; mach_timebase_info(&base);
    puts("monotonic_s,host_rss,host_footprint,runtime_rss,runtime_footprint,runtime_cpu_ns,runtime_lifetime_max_footprint");
    while (1) {
        struct rusage_info_v4 h = {0}, r = {0};
        if (proc_pid_rusage(host, RUSAGE_INFO_V4, (rusage_info_t *)&h) ||
            proc_pid_rusage(runtime, RUSAGE_INFO_V4, (rusage_info_t *)&r)) break;
        struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t);
        printf("%.6f,%llu,%llu,%llu,%llu,%llu,%llu\n", t.tv_sec+t.tv_nsec/1e9,
               h.ri_resident_size,h.ri_phys_footprint,r.ri_resident_size,r.ri_phys_footprint,
               (unsigned long long)((long double)(r.ri_user_time+r.ri_system_time)*base.numer/base.denom),r.ri_lifetime_max_phys_footprint);
        fflush(stdout); usleep(50000);
    }
    return 0;
}
