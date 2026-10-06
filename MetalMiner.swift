import Foundation
import Metal
func decode(_ hex:String) throws -> Data {
 guard hex.count%2==0 else {throw NSError(domain:"hex",code:1)}
 var d=Data(); var i=hex.startIndex
 while i<hex.endIndex {let j=hex.index(i,offsetBy:2);guard let b=UInt8(hex[i..<j],radix:16) else {throw NSError(domain:"hex",code:2)};d.append(b);i=j}
 return d
}
func encoded(_ p:UnsafeRawBufferPointer)->String {p.map {String(format:"%02x",$0)}.joined()}
func buffer(_ data:Data,_ device:MTLDevice)->MTLBuffer {data.withUnsafeBytes {device.makeBuffer(bytes:$0.baseAddress!,length:data.count,options:.storageModeShared)!}}
do {
 guard let device=MTLCreateSystemDefaultDevice(),let queue=device.makeCommandQueue() else {throw NSError(domain:"Metal unavailable",code:1)}
 let source=try String(contentsOfFile:"noid.metal",encoding:.utf8)
 let tower=source.contains("#define TOWER_STATE")
 let small=tower ? try String(contentsOfFile:"tower-small.metal",encoding:.utf8):""
 let library=try device.makeLibrary(source:"#include <metal_stdlib>\nusing namespace metal;\n"+small+source,options:nil)
 let pipeline=try device.makeComputePipelineState(function:library.makeFunction(name:"noid_hash")!)
 let tables=buffer(try Data(contentsOf:URL(fileURLWithPath:"tables.bin")),device)
 let rounds=buffer(try Data(contentsOf:URL(fileURLWithPath:tower ? "rounds-tower.bin":"rounds.bin")),device)
 fputs("Metal device: \(device.name)\n",stderr)
 while let line=readLine() {
  let v=try JSONSerialization.jsonObject(with:Data(line.utf8)) as! [String:Any]
  let header=try decode(v["header"] as! String)
  let count=v["count"] as! Int
  let base=UInt64(v["base"] as! String)!,prefix=UInt64(v["prefix"] as! String)!
  guard header.count==256,count>0,count<=1048576,base<=UInt64.max-UInt64(count) else {throw NSError(domain:"invalid request",code:1)}
  let optimized=v["state"] as? String
  let hb=buffer(optimized == nil ? header : try decode(v["flat"] as! String),device)
  let state=buffer(optimized == nil ? Data(repeating:0,count:64) : try decode(optimized!),device)
  let targetData=try decode(v["target"] as? String ?? String(repeating:"ff",count:32))
  guard targetData.count==32 else {throw NSError(domain:"target",code:1)}
  let fast=(v["digests"] as? Bool) != true && targetData.contains(where:{$0 != 255})
  let tb=buffer(targetData,device)
  let found=buffer(Data(repeating:0,count:4),device)
  let args:[UInt64]=[base,prefix,UInt64(count),optimized == nil ? 0 : 1,fast ? 1:0]
  let ab=args.withUnsafeBytes {device.makeBuffer(bytes:$0.baseAddress!,length:$0.count,options:.storageModeShared)!}
  let output=device.makeBuffer(length:fast ? 2048:count*32,options:.storageModeShared)!
  let start=Date()
  let cb=queue.makeCommandBuffer()!,encoder=cb.makeComputeCommandEncoder()!
  encoder.setComputePipelineState(pipeline)
  for (i,b) in [hb,ab,output,tables,rounds,state,tb,found].enumerated(){encoder.setBuffer(b,offset:0,index:i)}
  let threads=v["threads"] as? Int ?? 64
  encoder.dispatchThreads(MTLSize(width:count,height:1,depth:1),threadsPerThreadgroup:MTLSize(width:min(max(32,threads),pipeline.maxTotalThreadsPerThreadgroup),height:1,depth:1))
  encoder.endEncoding();cb.commit();cb.waitUntilCompleted()
  if let error=cb.error {throw error}
  let elapsed=Date().timeIntervalSince(start)
  let raw=UnsafeRawBufferPointer(start:output.contents(),count:output.length)
  var result:[String:Any]=["count":count,"seconds":elapsed,"hashrate":Double(count)/elapsed]
  if (v["digests"] as? Bool)==true {result["digests"]=(0..<count).map {encoded(UnsafeRawBufferPointer(rebasing:raw[($0*32)..<($0*32+32)]))}}
  if let t=v["target"] as? String {
   let target=Array(try decode(t));guard target.count==32 else {throw NSError(domain:"target",code:1)}
   var winners:[String]=[]
   if fast {
    let hits=Int(found.contents().load(as:UInt32.self))
    guard hits<=256 else {throw NSError(domain:"candidate overflow",code:1)}
    winners=(0..<hits).map{String(output.contents().load(fromByteOffset:$0*8,as:UInt64.self))}
   } else {for n in 0..<count {
    var lt=false
    for j in stride(from:31,through:0,by:-1){let a=raw[n*32+j],b=target[j];if a != b {lt=a<b;break}}
    if lt {winners.append(String(base+UInt64(n)))}
   }}
   result["nonces"]=winners
  }
  let data=try JSONSerialization.data(withJSONObject:result,options:.sortedKeys)
  print(String(data:data,encoding:.utf8)!);fflush(stdout)
 }
} catch {fputs("Metal miner failed: \(error)\n",stderr);exit(1)}
