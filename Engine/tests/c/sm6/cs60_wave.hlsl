// SM 6.0 wave operations: per thread, the lane count, its lane index, a prefix sum and a wave-wide sum
RWStructuredBuffer<uint> o : register(u0);
[numthreads(64, 1, 1)] void main(uint3 id : SV_DispatchThreadID) {
  uint i = id.x * 4;
  o[i + 0] = WaveGetLaneCount();
  o[i + 1] = WaveGetLaneIndex();
  o[i + 2] = WavePrefixSum(1u);
  o[i + 3] = WaveActiveSum(id.x);
}
