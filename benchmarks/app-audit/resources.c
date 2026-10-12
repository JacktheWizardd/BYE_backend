#include <libproc.h>
#include <sys/resource.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>
#include <mach/mach_time.h>
#include <string.h>
#include <math.h>
#ifndef BYE_SAMPLE_INTERVAL_US
#define BYE_SAMPLE_INTERVAL_US 500000
#endif
int main(int argc, char **argv) {
    mach_timebase_info_data_t base;mach_timebase_info(&base);
    if (argc == 1) {
        struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);
        printf("{\"numerator\":%u,\"denominator\":%u,\"mach_uptime_s\":%.9Lf,\"clock_monotonic_s\":%.9f}\n",base.numer,base.denom,
               (long double)mach_absolute_time()*base.numer/base.denom/1e9,t.tv_sec+t.tv_nsec/1e9);
        return 0;
    }
    if (argc == 2 && strcmp(argv[1],"--self-test")==0) {
        struct rusage_info_v4 a={0},b={0};struct rusage x={0},y={0};
        proc_pid_rusage(getpid(),RUSAGE_INFO_V4,(rusage_info_t *)&a);getrusage(RUSAGE_SELF,&x);
        volatile double sum=0;for(int i=0;i<20000000;i++)sum+=i*0.0001;
        proc_pid_rusage(getpid(),RUSAGE_INFO_V4,(rusage_info_t *)&b);getrusage(RUSAGE_SELF,&y);
        double calibrated=(long double)(b.ri_user_time+b.ri_system_time-a.ri_user_time-a.ri_system_time)*base.numer/base.denom/1e9;
        double reference=(y.ru_utime.tv_sec-x.ru_utime.tv_sec)+(y.ru_utime.tv_usec-x.ru_utime.tv_usec)/1e6+
                         (y.ru_stime.tv_sec-x.ru_stime.tv_sec)+(y.ru_stime.tv_usec-x.ru_stime.tv_usec)/1e6;
        printf("{\"proc_cpu_s\":%.9f,\"getrusage_cpu_s\":%.9f,\"difference_s\":%.9f,\"passed\":%s}\n",calibrated,reference,fabs(calibrated-reference),fabs(calibrated-reference)<0.005?"true":"false");
        return fabs(calibrated-reference)<0.005?0:1;
    }
    if (argc != 2) return 64;
    pid_t pid = atoi(argv[1]);
    puts("monotonic_s,pid,rss_bytes,physical_footprint_bytes,lifetime_peak_footprint_bytes,cpu_ns");
    while (1) {
        struct rusage_info_v4 r = {0};
        int error = proc_pid_rusage(pid,RUSAGE_INFO_V4,(rusage_info_t *)&r);
        if (error) { fprintf(stderr,"proc_pid_rusage failed for %d\n",pid); return 1; }
        long double seconds=(long double)mach_absolute_time()*base.numer/base.denom/1e9;
        unsigned long long cpu=(long double)(r.ri_user_time+r.ri_system_time)*base.numer/base.denom;
        printf("%.6Lf,%d,%llu,%llu,%llu,%llu\n",seconds,pid,
               r.ri_resident_size,r.ri_phys_footprint,r.ri_lifetime_max_phys_footprint,cpu);
        fflush(stdout);usleep(BYE_SAMPLE_INTERVAL_US);
    }
}
