/* miroe W1 research hook (not for shipping): wraps -[MTLDevice newBufferWithBytesNoCopy:length:options:deallocator:]
 * in a Wine process. MIROE_W1_HOOK=log|touch|noexec. Logs how many placed buffers are made, whether their memory is
 * page aligned and executable, and optionally touches or drops PROT_EXEC before Metal gets the memory. */
#import <Metal/Metal.h>
#import <objc/runtime.h>
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
static IMP orig; static int mode; static FILE *out;
static atomic_long n_calls, n_exec, n_unaligned, n_bytes;
static int prot_of(void *p) {
  mach_vm_address_t a = (mach_vm_address_t)p; mach_vm_size_t s = 0; vm_region_basic_info_data_64_t info;
  mach_msg_type_number_t cnt = VM_REGION_BASIC_INFO_COUNT_64; mach_port_t obj;
  if (mach_vm_region(mach_task_self(), &a, &s, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info, &cnt, &obj)) return -1;
  return info.protection;
}
static id hooked(id self, SEL sel, void *ptr, NSUInteger len, MTLResourceOptions opts, void (^dealloc)(void *, NSUInteger)) {
  long k = atomic_fetch_add(&n_calls, 1);
  int prot = prot_of(ptr); long pg = getpagesize();
  if (prot > 0 && (prot & VM_PROT_EXECUTE)) atomic_fetch_add(&n_exec, 1);
  if (((uintptr_t)ptr & (pg - 1)) || (len & (pg - 1))) atomic_fetch_add(&n_unaligned, 1);
  atomic_fetch_add(&n_bytes, (long)len);
  if (k < 12 && out) fprintf(out, "w1-hook: #%ld ptr %p len %lu prot %c%c%c\n", k, ptr, (unsigned long)len,
                             prot & 1 ? 'r' : '-', prot & 2 ? 'w' : '-', prot & 4 ? 'x' : '-');
  if (mode == 1) { volatile char *v = ptr; long s = 0; for (NSUInteger i = 0; i < len; i += 4096) s += v[i]; (void)s; }
  if (mode == 2) {
    uintptr_t b = (uintptr_t)ptr & ~(uintptr_t)(pg - 1), e = ((uintptr_t)ptr + len + pg - 1) & ~(uintptr_t)(pg - 1);
    mprotect((void *)b, e - b, PROT_READ | PROT_WRITE);
  }
  return ((id (*)(id, SEL, void *, NSUInteger, MTLResourceOptions, id))orig)(self, sel, ptr, len, opts, dealloc);
}
static void report(void) {
  if (out) fprintf(out, "w1-hook: mode %d, %ld placed buffers, %ld on executable memory, %ld unaligned, %ld MB\n",
                   mode, atomic_load(&n_calls), atomic_load(&n_exec), atomic_load(&n_unaligned), atomic_load(&n_bytes) >> 20);
}
__attribute__((constructor)) static void init(void) {
#if !defined(__x86_64__)
  return; /* only Wine's Rosetta processes */
#endif
  const char *m = getenv("MIROE_W1_HOOK"); const char *path = getenv("MIROE_W1_HOOK_LOG");
  if (!m) return;
  mode = !strcmp(m, "touch") ? 1 : !strcmp(m, "noexec") ? 2 : 0;
  out = path ? fopen(path, "a") : NULL; if (out) setvbuf(out, NULL, _IOLBF, 0);
  @autoreleasepool {
    id<MTLDevice> d = MTLCreateSystemDefaultDevice(); if (!d) return;
    Method meth = class_getInstanceMethod([(NSObject *)d class], @selector(newBufferWithBytesNoCopy:length:options:deallocator:));
    if (!meth) return;
    orig = method_setImplementation(meth, (IMP)hooked);
    if (out) fprintf(out, "w1-hook: pid %d, mode %s, class %s\n", getpid(), m, class_getName([(NSObject *)d class]));
  }
  atexit(report);
}
