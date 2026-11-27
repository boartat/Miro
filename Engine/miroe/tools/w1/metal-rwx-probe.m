/* miroe W1 probe: Metal buffers made with newBufferWithBytesNoCopy over RW vs RWX memory (what DXMT's CpuPlaced
 * does for 32-bit programs, where Wine adds PROT_EXEC when DEP is off). No Wine involved. */
#import <Metal/Metal.h>
#include <mach/mach_time.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <sys/mman.h>
static double ms(uint64_t a, uint64_t b) { mach_timebase_info_data_t t; mach_timebase_info(&t); return (b - a) * 1e-6 * t.numer / t.denom; }
static void run(id<MTLDevice> dev, id<MTLCommandQueue> q, const char *name, int prot, size_t size, int frames) {
  char *mem = mmap(NULL, size, prot, MAP_PRIVATE | MAP_ANON, -1, 0);
  if (mem == MAP_FAILED) { perror("mmap"); return; }
  uint64_t t0 = mach_absolute_time();
  id<MTLBuffer> placed = [dev newBufferWithBytesNoCopy:mem length:size options:MTLResourceStorageModeShared deallocator:nil];
  id<MTLBuffer> priv = [dev newBufferWithLength:size options:MTLResourceStorageModePrivate];
  uint64_t t1 = mach_absolute_time();
  double cpu_w = 0, cpu_r = 0, gpu = 0, worst = 0; volatile long sum = 0;
  for (int f = 0; f < frames; f++) {
    uint64_t a = mach_absolute_time();
    memset(mem, f, size / 2);                                   /* CPU writes, like a staging upload */
    uint64_t b = mach_absolute_time();
    id<MTLCommandBuffer> cb = [q commandBuffer];
    id<MTLBlitCommandEncoder> bl = [cb blitCommandEncoder];
    [bl copyFromBuffer:placed sourceOffset:0 toBuffer:priv destinationOffset:0 size:size / 2];
    [bl copyFromBuffer:priv sourceOffset:0 toBuffer:placed destinationOffset:size / 2 size:size / 2];   /* GPU writes back */
    [bl endEncoding]; [cb commit]; [cb waitUntilCompleted];
    uint64_t c = mach_absolute_time();
    for (size_t i = size / 2; i < size; i += 4096) sum += mem[i];   /* CPU reads what the GPU wrote */
    uint64_t d = mach_absolute_time();
    cpu_w += ms(a, b); gpu += ms(b, c); cpu_r += ms(c, d);
    if (ms(a, d) > worst) worst = ms(a, d);
    if (getenv("TRACE") && ms(a, d) > 5) printf("  %s frame %d: %.1f ms (read %.1f)\n", name, f, ms(a, d), ms(c, d));
  }
  printf("%-4s create %7.2f ms | per frame: CPU write %7.3f  GPU %7.3f  CPU read %7.3f  worst frame %8.2f ms\n", name, ms(t0, t1), cpu_w / frames, gpu / frames, cpu_r / frames, worst);
  munmap(mem, size);
}
int main(int argc, char **argv) {
  @autoreleasepool {
    id<MTLDevice> dev = MTLCreateSystemDefaultDevice(); id<MTLCommandQueue> q = [dev newCommandQueue];
    size_t size = (size_t)(argc > 1 ? atoi(argv[1]) : 8) << 20; int frames = argc > 2 ? atoi(argv[2]) : 20;
    printf("%s, %zu MB, %d frames\n", dev.name.UTF8String, size >> 20, frames);
    for (int k = 0; k < 2; k++) {
      run(dev, q, "rw", PROT_READ | PROT_WRITE, size, frames);
      run(dev, q, "rwx", PROT_READ | PROT_WRITE | PROT_EXEC, size, frames);
    }
  }
  return 0;
}
