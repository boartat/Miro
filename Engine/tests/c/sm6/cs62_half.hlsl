// SM 6.2 native 16-bit types (compiled with -enable-16bit-types)
RWStructuredBuffer<uint> o : register(u0);
[numthreads(64, 1, 1)] void main(uint3 id : SV_DispatchThreadID) {
  float16_t f = (float16_t)id.x * (float16_t)0.25 * (float16_t)8.0;   // 2 * i, exact for i < 256
  uint16_t u = (uint16_t)id.x * (uint16_t)300;                         // wraps modulo 65536
  o[id.x] = (uint)f | ((uint)u << 16);
}
