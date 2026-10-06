use noid_core::{hardware::{tower_to_flat_u128 as tf,flat_to_tower_u128 as ft,clmul_gcm,square_flat_u128},Block128};
use noid_poseidon2b::{native::{domain::{TAG_POWHDR,capacity_iv_flat},permutation::{ROUND_CONSTANTS,permute_flat_u128}},batch::FixedFieldNonceBatch};
use std::{fs,io::{self,BufRead}};
use rayon::prelude::*;
fn main() {
 let args:Vec<String>=std::env::args().collect();
 if args.get(1).map(String::as_str)==Some("export") {
  let mut lut=Vec::new();
  for kind in 0..15 { for byte in 0..16 { for v in 0..256u128 {
   let x=v << (byte*8);
   let y=match kind {0=>tf(x),1=>ft(x),2=>square_flat_u128(x),3..=10=>clmul_gcm(x,tf((kind-3) as u128)),_=>clmul_gcm(x,tf([0x20,0x2000,0x200,0x800][kind-11]))};
   lut.extend_from_slice(&y.to_le_bytes());
  }}}
  for c in [0x20u128,0x2000,0x200,0x800] {for x in 0..65536u128 {
   let v=ft(clmul_gcm(tf(x),tf(c)));assert!(v<65536);lut.extend_from_slice(&(v as u16).to_le_bytes());
  }}
  fs::write("tables.bin",lut).unwrap();
  let mut rc=Vec::new();
  for row in ROUND_CONSTANTS {for x in row {rc.extend_from_slice(&tf(x).to_le_bytes());}}
  for x in capacity_iv_flat(TAG_POWHDR) {rc.extend_from_slice(&x.to_le_bytes());}
  fs::write("rounds.bin",rc).unwrap();
  let mut tower_rc=Vec::new();
  for row in ROUND_CONSTANTS {for x in row {tower_rc.extend_from_slice(&x.to_le_bytes());}}
  for x in capacity_iv_flat(TAG_POWHDR) {tower_rc.extend_from_slice(&ft(x).to_le_bytes());}
  fs::write("rounds-tower.bin",tower_rc).unwrap();
  let mut columns=String::from("constant uchar SMALL[8][256]={\n");
  for c in 0..8u128 {let v:Vec<String>=(0..256u128).map(|x|{let v=ft(clmul_gcm(tf(x),tf(c)));assert!(v<256);v.to_string()}).collect();columns.push_str(&format!("{{{}}},\n",v.join(",")));}
  columns.push_str("};\n");fs::write("tower-small.metal",columns).unwrap();return;
 }
 for line in io::stdin().lock().lines() {
  let v:serde_json::Value=serde_json::from_str(&line.unwrap()).unwrap();
  let header=hex::decode(v["header"].as_str().unwrap()).unwrap(); assert_eq!(header.len(),256);
  if v["prepare"].as_bool()==Some(true) {
   let iv=capacity_iv_flat(TAG_POWHDR);let mut state=[0,0,iv[0],iv[1]];
   let flat:Vec<u128>=header.chunks_exact(16).map(|x|tf(u128::from_le_bytes(x.try_into().unwrap()))).collect();
   for p in 0..5 {state[0]^=flat[p*2];state[1]^=flat[p*2+1];permute_flat_u128(&mut state);}
   println!("{}",serde_json::json!({"state":hex::encode(state.iter().flat_map(|x|x.to_le_bytes()).collect::<Vec<_>>()),"flat":hex::encode(flat.iter().flat_map(|x|x.to_le_bytes()).collect::<Vec<_>>())}));continue;
  }
  let count=v["count"].as_u64().unwrap() as usize; assert!(count<=65536);
  let base:u64=v["base"].as_str().unwrap().parse().unwrap();
  let prefix:u64=v["prefix"].as_str().unwrap().parse().unwrap();
  assert!(base.checked_add(count as u64).is_some());
  let fields:Vec<Block128>=header.chunks_exact(16).map(|x|Block128(u128::from_le_bytes(x.try_into().unwrap()))).collect();
  let start=std::time::Instant::now();
  let mut out=vec![[0u8;32];count];
  out.par_chunks_mut(256).enumerate().for_each(|(chunk,values)|{
   let mut h=FixedFieldNonceBatch::new(TAG_POWHDR,&fields,10);
   h.hash_into(((prefix as u128)<<64)|(base as u128+chunk as u128*256),values);
  });
  if let Some(t)=v["target"].as_str() {
   let target=hex::decode(t).unwrap();assert_eq!(target.len(),32);
   let nonces:Vec<String>=out.iter().enumerate().filter(|(_,d)|d.iter().rev().cmp(target.iter().rev())==std::cmp::Ordering::Less).map(|(i,_)|(base+i as u64).to_string()).collect();
   let seconds=start.elapsed().as_secs_f64();
   println!("{}",serde_json::json!({"nonces":nonces,"seconds":seconds,"hashrate":count as f64/seconds,"count":count}));
  } else {println!("{}",serde_json::json!({"digests":out.iter().map(hex::encode).collect::<Vec<_>>()}));}
 }
}
