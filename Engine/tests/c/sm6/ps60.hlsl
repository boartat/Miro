// SM 6.0 pixel shader: the colour of root constant b0, halved right of x = 128
cbuffer c : register(b0) { float4 colour; };
float4 main(float4 pos : SV_Position) : SV_Target { return pos.x < 128 ? colour : float4(colour.rgb * 0.5, colour.a); }
