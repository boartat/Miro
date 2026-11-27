/* miroe W1 probe 2: which part of "RWX memory under a no-copy Metal buffer" costs the ~1.2 s stall. */
#import <Metal/Metal.h>
#include <mach/mach_time.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
static double ms(uint64_t a, uint64_t b) { mach_timebase_info_data_t t; mach_timebase_info(&t); return (b - a) * 1e-6 * t.numer / t.denom; }
static id<MTLDevice> dev; static id<MTLCommandQueue> q;
enum { GPU_WRITES = 1, GPU_READS_ONLY = 2 };
/* returns the worst CPU read after GPU work, in ms */
static int prefault_after, prefault_read;
static double trial(const char *name, int prot, int drop_exec_after_create, int prefault, int gpu, int add_exec_after_create) {
  size_t size = 4 << 20;
  char *mem = mmap(NULL, size, prot, MAP_PRIVATE | MAP_ANON, -1, 0);
  volatile char *vm = mem; volatile long acc = 0;
  if (prefault && !prefault_after) { if (prefault_read) for (size_t i = 0; i < size; i += 4096) acc += vm[i]; else for (size_t i = 0; i < size; i += 4096) vm[i] = vm[i]; }
  id<MTLBuffer> placed = [dev newBufferWithBytesNoCopy:mem length:size options:MTLResourceStorageModeShared deallocator:nil];
  if (prefault && prefault_after) for (size_t i = 0; i < size; i += 4096) vm[i] = vm[i];
  if (drop_exec_after_create) mprotect(mem, size, PROT_READ | PROT_WRITE);
  if (add_exec_after_create) mprotect(mem, size, PROT_READ | PROT_WRITE | PROT_EXEC);
  id<MTLBuffer> priv = [dev newBufferWithLength:size options:MTLResourceStorageModePrivate];
  double worst = 0; volatile long sum = 0;
  for (int f = 0; f < 6; f++) {
    memset(mem, f, size / 2);
    id<MTLCommandBuffer> cb = [q commandBuffer]; id<MTLBlitCommandEncoder> bl = [cb blitCommandEncoder];
    [bl copyFromBuffer:placed sourceOffset:0 toBuffer:priv destinationOffset:0 size:size / 2];
    if (gpu == GPU_WRITES) [bl copyFromBuffer:priv sourceOffset:0 toBuffer:placed destinationOffset:size / 2 size:size / 2];
    [bl endEncoding]; [cb commit]; [cb waitUntilCompleted];
    uint64_t c = mach_absolute_time();
    for (size_t i = 0; i < size; i += 4096) sum += mem[i];
    double r = ms(c, mach_absolute_time()); if (r > worst) worst = r;
  }
  printf("%-44s worst CPU read %8.2f ms\n", name, worst);
  munmap(mem, size); return worst;
}
int main(void) {
  @autoreleasepool {
    dev = MTLCreateSystemDefaultDevice(); q = [dev newCommandQueue];
    int RW = PROT_READ | PROT_WRITE, RWX = RW | PROT_EXEC;
    if (getenv("ONLY_PREFAULT")) {
      for (int k = 0; k < 2; k++) {
        prefault_after = 0; prefault_read = 0; trial("rwx, touch-write before create", RWX, 0, 1, GPU_WRITES, 0);
        prefault_after = 0; prefault_read = 1; trial("rwx, touch-read before create", RWX, 0, 1, GPU_WRITES, 0);
        prefault_after = 1; prefault_read = 0; trial("rwx, touch-write after create, before GPU", RWX, 0, 1, GPU_WRITES, 0);
      }
      return 0;
    }
    for (int k = 0; k < 2; k++) {
      trial("rw, GPU writes", RW, 0, 0, GPU_WRITES, 0);
      trial("rwx, GPU writes", RWX, 0, 0, GPU_WRITES, 0);
      trial("rwx, GPU only reads", RWX, 0, 0, GPU_READS_ONLY, 0);
      trial("rwx, prefaulted by CPU, GPU writes", RWX, 0, 1, GPU_WRITES, 0);
      trial("rwx, exec dropped after create, GPU writes", RWX, 1, 0, GPU_WRITES, 0);
      trial("rw, exec added after create, GPU writes", RW, 0, 0, GPU_WRITES, 1);
    }
  }
  return 0;
}
