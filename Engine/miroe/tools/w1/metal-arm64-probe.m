/* miroe W1 on ARM64: can memory under a Metal no-copy buffer be writable+executable in a native arm64 process, and
 * does the Rosetta stall happen there? Plain RWX (refused by W^X), RW flipped to RX after an execute, and MAP_JIT. */
#import <Metal/Metal.h>
#include <errno.h>
#include <mach/mach_time.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
static double ms(uint64_t a, uint64_t b) { mach_timebase_info_data_t t; mach_timebase_info(&t); return (b - a) * 1e-6 * t.numer / t.denom; }
static id<MTLDevice> dev; static id<MTLCommandQueue> q;
static void trial(const char *name, char *mem, size_t size) {
  id<MTLBuffer> placed = [dev newBufferWithBytesNoCopy:mem length:size options:MTLResourceStorageModeShared deallocator:nil];
  if (!placed) { printf("%-40s Metal refused the memory\n", name); return; }
  id<MTLBuffer> priv = [dev newBufferWithLength:size options:MTLResourceStorageModePrivate];
  double worst = 0; volatile long sum = 0;
  for (int f = 0; f < 6; f++) {
    id<MTLCommandBuffer> cb = [q commandBuffer]; id<MTLBlitCommandEncoder> bl = [cb blitCommandEncoder];
    [bl copyFromBuffer:priv sourceOffset:0 toBuffer:placed destinationOffset:0 size:size];
    [bl endEncoding]; [cb commit]; [cb waitUntilCompleted];
    uint64_t c = mach_absolute_time();
    for (size_t i = 0; i < size; i += 16384) sum += mem[i];
    double r = ms(c, mach_absolute_time()); if (r > worst) worst = r;
  }
  printf("%-40s worst CPU read after GPU write %8.3f ms\n", name, worst);
}
int main(void) {
  @autoreleasepool {
    dev = MTLCreateSystemDefaultDevice(); q = [dev newCommandQueue];
    size_t size = 4 << 20;
    char *rwx = mmap(NULL, size, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANON, -1, 0);
    printf("mmap RWX: %s\n", rwx == MAP_FAILED ? strerror(errno) : "allowed");
    char *rw = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    printf("mprotect RW -> RWX: %s\n", mprotect(rw, size, PROT_READ | PROT_WRITE | PROT_EXEC) ? strerror(errno) : "allowed");
    trial("RW", rw, size);
    char *rx = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    memset(rx, 0, size); mprotect(rx, size, PROT_READ | PROT_EXEC);   /* what a W^X flip after an execute leaves */
    trial("RX (after a W^X flip)", rx, size);
    char *jit = mmap(NULL, size, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANON | MAP_JIT, -1, 0);
    if (jit == MAP_FAILED) printf("MAP_JIT: %s\n", strerror(errno));
    else { pthread_jit_write_protect_np(0); trial("MAP_JIT (RWX, writable for this thread)", jit, size); }
  }
  return 0;
}
