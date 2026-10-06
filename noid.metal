// Poseidon2b parameters and basis maps are exported from pinned official Rust source.
#include <metal_stdlib>
#define TOWER_STATE 1
using namespace metal;
typedef ulong2 F;
inline F linear(F x, uint k, device const F* lut) {
 F o=F(0);
 for(uint i=0;i<8;i++) o ^= lut[k*4096+i*256+uint((x.x>>(i*8))&255)];
 for(uint i=0;i<8;i++) o ^= lut[k*4096+(i+8)*256+uint((x.y>>(i*8))&255)];
 return o;
}
inline uint4 times2(uint4 a) {return uint4((a.x<<1)^((a.w>>31)*0x87u),(a.y<<1)|(a.x>>31),(a.z<<1)|(a.y>>31),(a.w<<1)|(a.z>>31));}
inline F mul(F aa,F bb) {
 uint4 a=as_type<uint4>(aa),b=as_type<uint4>(bb);
 uint4 a1=times2(a),a2=times2(a1),a3=times2(a2),o=uint4(0);
 for(int word=3;word>=0;word--) for(int bit=28;bit>=0;bit-=4) {
  uint n=(b[word]>>bit)&15;
  uint carry=o.w>>28;
  o=uint4((o.x<<4)^carry^(carry<<1)^(carry<<2)^(carry<<7),(o.y<<4)|(o.x>>28),(o.z<<4)|(o.y>>28),(o.w<<4)|(o.z>>28));
  o ^= a & uint4(0u-(n&1));
  o ^= a1 & uint4(0u-((n>>1)&1));
  o ^= a2 & uint4(0u-((n>>2)&1));
  o ^= a3 & uint4(0u-((n>>3)&1));
 }
 return as_type<F>(o);
}
inline uint spread16(uint x) {
 x &= 0xffffu;x=(x|(x<<8))&0x00ff00ffu;x=(x|(x<<4))&0x0f0f0f0fu;
 x=(x|(x<<2))&0x33333333u;return (x|(x<<1))&0x55555555u;
}
inline uint4 shl128(uint4 a,uint n) {return uint4(a.x<<n,(a.y<<n)|(a.x>>(32-n)),(a.z<<n)|(a.y>>(32-n)),(a.w<<n)|(a.z>>(32-n)));}
inline F square(F a) {
 uint4 x=as_type<uint4>(a);
 uint4 low=uint4(spread16(x.x),spread16(x.x>>16),spread16(x.y),spread16(x.y>>16));
 uint4 high=uint4(spread16(x.z),spread16(x.z>>16),spread16(x.w),spread16(x.w>>16));
 low ^= high^shl128(high,1)^shl128(high,2)^shl128(high,7);
 uint carry=(high.w>>31)^(high.w>>30)^(high.w>>25);
 low.x ^= carry^(carry<<1)^(carry<<2)^(carry<<7);
 return as_type<F>(low);
}
inline F sbox(F a,device const F* lut) {
 a=linear(a,0,lut);
 F a2=square(a),a4=square(a2);
 return linear(mul(mul(a,a2),a4),1,lut);
}
inline F smallmul(F a,uint c) {
 uint4 x=as_type<uint4>(a),o=uint4(0);
 for(uint i=0;i<4;i++) for(uint j=0;j<4;j++) o[i] |= uint(SMALL[c][(x[i]>>(j*8))&255])<<(j*8);
 return as_type<F>(o);
}
inline F diag(F a,uint c,device const F* lut) {
 device const ushort* tab=reinterpret_cast<device const ushort*>(lut+61440)+c*65536;
 uint4 x=as_type<uint4>(a),o;
 for(uint i=0;i<4;i++) o[i]=uint(tab[x[i]&65535])|(uint(tab[x[i]>>16])<<16);
 return as_type<F>(o);
}
inline void full(thread F* s,device const F* lut) {
 F a=s[0],b=s[1],c=s[2],d=s[3];
 s[0]=smallmul(a,5)^smallmul(b,7)^c^smallmul(d,3);
 s[1]=smallmul(a,4)^smallmul(b,6)^c^d;
 s[2]=a^smallmul(b,3)^smallmul(c,5)^smallmul(d,7);
 s[3]=a^b^smallmul(c,4)^smallmul(d,6);
}
inline void permute(thread F* s,device const F* lut,device const F* rc) {
 full(s,lut);
 for(uint r=0;r<66;r++) {
  if(r<4 || r>=62) {
   for(uint i=0;i<4;i++) s[i]=sbox(s[i]^rc[i*66+r],lut);
   full(s,lut);
  } else {
   s[0]=sbox(s[0]^rc[r],lut);
   F total=s[0]^s[1]^s[2]^s[3];
   for(uint i=0;i<4;i++) s[i]=total^s[i]^diag(s[i],i,lut);
  }
 }
}
kernel void noid_hash(device const F* header [[buffer(0)]],device const ulong* args [[buffer(1)]],device F* out [[buffer(2)]],device const F* lut [[buffer(3)]],device const F* rc [[buffer(4)]],device const F* prepared [[buffer(5)]],device const uint* target [[buffer(6)]],device atomic_uint* found [[buffer(7)]],uint idx [[thread_position_in_grid]]) {
 if(idx>=args[2]) return;
 F s[4]={F(0),F(0),rc[264],rc[265]};
 if(args[3]) for(uint i=0;i<4;i++) s[i]=linear(prepared[i],1,lut);
 for(uint p=args[3]?5:0;p<8;p++) {
  F a=header[p*2],b=header[p*2+1];
  if(args[3]) {a=linear(a,1,lut);b=linear(b,1,lut);}
  if(p==5) a=F(args[0]+idx,args[1]);
  s[0]^=a;s[1]^=b;
  permute(s,lut,rc);
 }
 F d0=s[0],d1=s[1];
 if(args[4]) {
  uint4 lo=as_type<uint4>(d0),hi=as_type<uint4>(d1);
  bool less=false;
  for(int j=7;j>=0;j--) {uint v=j>=4?hi[j-4]:lo[j];if(v!=target[j]){less=v<target[j];break;}}
  if(less){uint slot=atomic_fetch_add_explicit(found,1,memory_order_relaxed);if(slot<256) reinterpret_cast<device ulong*>(out)[slot]=args[0]+idx;}
 } else {out[idx*2]=d0;out[idx*2+1]=d1;}
}
