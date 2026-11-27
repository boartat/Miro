// SM 6.6 dynamic resources: the UAV is taken from the descriptor heap by an index in a root constant
cbuffer c : register(b0) { uint index; };
[numthreads(64, 1, 1)] void main(uint3 id : SV_DispatchThreadID) {
  RWStructuredBuffer<uint> o = ResourceDescriptorHeap[index];
  o[id.x] = id.x * 3 + 12345;
}
