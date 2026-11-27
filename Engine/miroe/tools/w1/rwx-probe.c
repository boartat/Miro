/* miroe W1 probe: what does a writable+executable page cost an x86_64 process under Rosetta, and does Rosetta
 * raise a fault when x86 code runs from a page without PROT_EXEC (needed for lazy exec)? No Wine involved. */
#include <mach/mach_time.h>
#include <setjmp.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
static double ms(uint64_t a, uint64_t b) { mach_timebase_info_data_t t; mach_timebase_info(&t); return (b - a) * 1e-6 * t.numer / t.denom; }
static void touch(const char *name, int prot, size_t size, int rounds) {
  char *p = mmap(NULL, size, prot, MAP_PRIVATE | MAP_ANON, -1, 0);
  if (p == MAP_FAILED) { perror("mmap"); return; }
  long pg = getpagesize();
  uint64_t t0 = mach_absolute_time();
  for (size_t i = 0; i < size; i += pg) p[i] = 1;            /* first write */
  uint64_t t1 = mach_absolute_time();
  volatile long sum = 0;
  for (int r = 0; r < rounds; r++) for (size_t i = 0; i < size; i += pg) sum += p[i];   /* later reads */
  uint64_t t2 = mach_absolute_time();
  memset(p, 2, size);                                           /* bulk write */
  uint64_t t3 = mach_absolute_time();
  printf("%-4s first write %8.2f ms  reads %8.2f ms  memset %8.2f ms  (%zu MB, page %ld)\n", name, ms(t0, t1), ms(t1, t2), ms(t2, t3), size >> 20, pg);
  munmap(p, size);
}
static sigjmp_buf jb; static volatile int faults; static char *code_page;
static void on_fault(int sig, siginfo_t *si, void *uc) {
  faults++;
  if ((char *)si->si_addr >= code_page && (char *)si->si_addr < code_page + getpagesize() && faults < 3) {
    mprotect(code_page, getpagesize(), PROT_READ | PROT_WRITE | PROT_EXEC);   /* lazy exec: grant and retry */
    return;
  }
  siglongjmp(jb, sig);
}
int main(int argc, char **argv) {
  size_t size = (argc > 1 ? atoi(argv[1]) : 64) << 20;
  for (int k = 0; k < 2; k++) {
    touch("rw", PROT_READ | PROT_WRITE, size, 4);
    touch("rwx", PROT_READ | PROT_WRITE | PROT_EXEC, size, 4);
  }
  struct sigaction sa = {0}; sa.sa_sigaction = on_fault; sa.sa_flags = SA_SIGINFO;
  sigaction(SIGSEGV, &sa, NULL); sigaction(SIGBUS, &sa, NULL);
  code_page = mmap(NULL, getpagesize(), PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
  const unsigned char ret42[] = {0xb8, 42, 0, 0, 0, 0xc3};      /* mov eax, 42; ret */
  memcpy(code_page, ret42, sizeof(ret42));
  int sig = sigsetjmp(jb, 1);
  if (!sig) {
    int v = ((int (*)(void))code_page)();
    printf("exec from RW page: returned %d after %d fault(s) -> %s\n", v, faults, faults ? "fault raised, lazy exec works" : "no fault: NX not enforced");
  } else {
    printf("exec from RW page: signal %d not recovered after %d fault(s)\n", sig, faults);
  }
  return 0;
}
