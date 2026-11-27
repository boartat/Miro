/* miroe W1 probe 3: Metal no-copy buffers made again over memory an earlier buffer used (heap reuse), and memory
 * that Wine-style reserves PROT_NONE and later mprotects. Prints every CPU access slower than 5 ms. */
#import <Metal/Metal.h>
#include <mach/mach_time.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
static double ms(uint64_t a, uint64_t b) { mach_timebase_info_data_t t; mach_timebase_info(&t); return (b - a) * 1e-6 * t.numer / t.denom; }
static id<MTLDevice> dev; static id<MTLCommandQueue> q;
static void scenario(const char *name, char *mem, size_t size, int recreate, int frames) {
  id<MTLBuffer> priv = [dev newBufferWithLength:size options:MTLResourceStorageModePrivate];
  id<MTLBuffer> placed = nil; int stalls = 0; double worst = 0, total = 0; volatile long sum = 0;
  volatile char *vm = mem;
  for (int f = 0; f < frames; f++) {
    for (size_t i = 0; i < size; i += 4096) sum += vm[i];          /* CPU touch before Metal (the W1 touch) */
    if (!placed || recreate) placed = [dev newBufferWithBytesNoCopy:mem length:size options:MTLResourceStorageModeShared deallocator:nil];
    uint64_t a = mach_absolute_time();
    memset(mem, f, size / 2);
    double w = ms(a, mach_absolute_time());
    id<MTLCommandBuffer> cb = [q commandBuffer]; id<MTLBlitCommandEncoder> bl = [cb blitCommandEncoder];
    [bl copyFromBuffer:placed sourceOffset:0 toBuffer:priv destinationOffset:0 size:size / 2];
    [bl copyFromBuffer:priv sourceOffset:0 toBuffer:placed destinationOffset:size / 2 size:size / 2];
    [bl endEncoding]; [cb commit]; [cb waitUntilCompleted];
    uint64_t c = mach_absolute_time();
    for (size_t i = 0; i < size; i += 4096) sum += vm[i];
    double r = ms(c, mach_absolute_time());
    double t = w + r; total += t; if (t > worst) worst = t;
    if (t > 5) { stalls++; if (stalls <= 3) printf("    %s frame %d: write %.1f ms, read %.1f ms\n", name, f, w, r); }
    if (recreate) placed = nil;                                        /* release, as a freed staging block */
  }
  printf("%-52s stalls %2d / %d  worst %8.2f ms  total %8.1f ms\n", name, stalls, frames, worst, total);
}
int main(int argc, char **argv) {
  @autoreleasepool {
    dev = MTLCreateSystemDefaultDevice(); q = [dev newCommandQueue];
    size_t size = 1 << 20; int frames = argc > 1 ? atoi(argv[1]) : 12;
    int RW = PROT_READ | PROT_WRITE, RWX = RW | PROT_EXEC;
    char *a = mmap(NULL, size, RW, MAP_PRIVATE | MAP_ANON, -1, 0);
    scenario("rw, buffer made again each frame", a, size, 1, frames);
    char *b = mmap(NULL, size, RWX, MAP_PRIVATE | MAP_ANON, -1, 0);
    scenario("rwx, one buffer", b, size, 0, frames);
    char *c = mmap(NULL, size, RWX, MAP_PRIVATE | MAP_ANON, -1, 0);
    scenario("rwx, buffer made again each frame", c, size, 1, frames);
    char *d = mmap(NULL, size, PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0); mprotect(d, size, RWX);
    scenario("reserved PROT_NONE, mprotect rwx, made again", d, size, 1, frames);
    char *e = mmap(NULL, size, PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0); mprotect(e, size, RW);
    scenario("reserved PROT_NONE, mprotect rw, made again", e, size, 1, frames);
  }
  return 0;
}
