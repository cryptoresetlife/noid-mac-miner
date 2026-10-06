import Foundation
import Network
import Darwin

enum MinerError: Error, CustomStringConvertible {
 case message(String)
 var description:String {if case .message(let s)=self{return s};return "错误"}
}
func validWallet(_ s:String)->Bool {
 let alphabet=Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l".utf8)
 guard s==s.lowercased(),s.hasPrefix("o1"),s.count>=14,s.count<=90 else{return false}
 var values:[UInt32]=[3,0,15] // Bech32 HRP expansion for "o".
 for c in s.dropFirst(2).utf8 {guard let n=alphabet.firstIndex(of:c) else{return false};values.append(UInt32(n))}
 var chk:UInt32=1
 let gen:[UInt32]=[0x3b6a57b2,0x26508e6d,0x1ea119fa,0x3d4233dd,0x2a1462b3]
 for v in values {let top=chk>>25;chk=((chk&0x1ffffff)<<5)^v;for i in 0..<5 {if (top>>i)&1 != 0 {chk ^= gen[i]}}}
 return chk==0x2bc830a3
}
func hexData(_ s:String)->Data? {
 guard s.count%2==0 else{return nil};var data=Data();var i=s.startIndex
 while i<s.endIndex {let j=s.index(i,offsetBy:2);guard let b=UInt8(s[i..<j],radix:16) else{return nil};data.append(b);i=j};return data
}
struct PoolJob {
 let id:String,header:String,target:String,prefix:String,domain:String
 let expires:Date
 init?(_ v:[String:Any]) {
  guard let id=v["job_id"] as? String,let h=v["pow_fields_hex"] as? String,hexData(h)?.count==256,
   let t=v["share_target_hex"] as? String,hexData(t)?.count==32,
   let p=v["nonce_prefix_hex"] as? String,hexData(p)?.count==8,
   let d=v["work_domain_id"] as? String,hexData(d)?.count==32,
   (v["nonce_field_index"] as? Int)==10,(v["nonce_bits"] as? Int)==64 else{return nil}
  self.id=id;header=h;target=t;prefix=p;domain=d
  expires=Date().addingTimeInterval(Double(min(600,max(1,v["expires_in_seconds"] as? Int ?? 60))))
 }
 var prefixValue:UInt64 {hexData(prefix)!.enumerated().reduce(0){$0 | UInt64($1.element)<<($1.offset*8)}}
}
enum LoadPolicy {
 static func duty(percent:Int,thermal:ProcessInfo.ThermalState,protect:Bool)->Double {
  let requested=Double(min(100,max(10,percent)))/100
  guard protect else{return requested}
  if thermal == .critical {return 0}
  if thermal == .serious {return min(requested,0.5)}
  return requested
 }
 static func pauseSeconds(busy:Double,duty:Double)->Double {guard duty>0 else{return 0};return max(0,busy*(1/duty-1))}
 static func retryDelay(_ attempt:Int)->Double {min(30,pow(2,Double(min(5,max(1,attempt)))))}
 static func thermalLabel(_ state:ProcessInfo.ThermalState)->String {
  switch state{case .nominal:return "正常";case .fair:return "温热";case .serious:return "过热，降低负载";case .critical:return "严重过热，暂停计算";@unknown default:return "未知"}
 }
}
final class HashProcess {
 let process=Process(),input=Pipe(),output=Pipe(),errors=Pipe(),errorLock=NSLock()
 var pending=Data()
 var errorText=""
 init(executable:URL,directory:URL,threads:Int=1) throws {
  process.executableURL=executable;process.currentDirectoryURL=directory
  var environment=ProcessInfo.processInfo.environment;environment["RAYON_NUM_THREADS"]=String(max(1,threads));process.environment=environment
  process.standardInput=input;process.standardOutput=output;process.standardError=errors
  errors.fileHandleForReading.readabilityHandler={[weak self] handle in
   let data=handle.availableData;guard !data.isEmpty,let self=self else{handle.readabilityHandler=nil;return}
   self.errorLock.lock();self.errorText=String((self.errorText+String(decoding:data,as:UTF8.self)).suffix(4096));self.errorLock.unlock()
  }
  try process.run()
 }
 func call(_ request:[String:Any]) throws -> [String:Any] {
  var data=try JSONSerialization.data(withJSONObject:request);data.append(10)
  try input.fileHandleForWriting.write(contentsOf:data)
  while true {
   if let n=pending.firstIndex(of:10){let line=pending.prefix(upTo:n);pending.removeSubrange(...n);return try JSONSerialization.jsonObject(with:line) as! [String:Any]}
   var bytes=[UInt8](repeating:0,count:65536)
   let n=bytes.withUnsafeMutableBytes {Darwin.read(output.fileHandleForReading.fileDescriptor,$0.baseAddress!,$0.count)}
   if n<0 {if errno==EINTR {continue};throw MinerError.message("计算管道读取失败")}
   if n==0 {errorLock.lock();let reason=errorText.trimmingCharacters(in:.whitespacesAndNewlines);errorLock.unlock();throw MinerError.message("计算进程已退出"+(reason.isEmpty ? "":"："+reason))};pending.append(contentsOf:bytes.prefix(n))
   if pending.count>8_000_000 {throw MinerError.message("计算输出异常")}
  }
 }
 func stop(){try? input.fileHandleForWriting.close();if process.isRunning{process.terminate()}}
}
final class PoolSession {
 let connection:NWConnection
 let queue=DispatchQueue(label:"noid.pool.\(UUID())")
 let lock=NSLock()
 var buffer=Data(),job:PoolJob?,authorized=false,namespace:String?,ended=false
 var submitID=100
 var retryable=false,failureReason="",lastMessage=ProcessInfo.processInfo.systemUptime
 let username:String,event:(String)->Void,share:(Bool,Bool)->Void
 init(wallet:String,worker:String,event:@escaping(String)->Void,share:@escaping(Bool,Bool)->Void) {
  username=wallet+"."+worker;self.event=event;self.share=share
  connection=NWConnection(host:"hk.innovlab.cc",port:19601,using:NWParameters(tls:NWProtocolTLS.Options()))
 }
 func start() {
  connection.stateUpdateHandler={[weak self] state in
   guard let self=self else{return}
   switch state {
   case .ready:self.event("TLS 已连接 InnovLab");self.send(["id":1,"method":"mining.subscribe","params":["noid-metal-mac/0.4"]]);self.receive()
   case .failed(let e):self.fail("矿池连接失败：\(e)",retry:true)
   default:break
   }
  };connection.start(queue:queue)
 }
 func send(_ v:[String:Any]) {
  guard let data=try? JSONSerialization.data(withJSONObject:v) else{return}
  connection.send(content:data+Data([10]),completion:.contentProcessed{[weak self] error in if let error=error {self?.fail("发送失败：\(error)",retry:true)}})
 }
 func receive() {
  connection.receive(minimumIncompleteLength:1,maximumLength:65536){[weak self] data,_,complete,error in
   guard let self=self else{return}
   if let data=data {self.lock.lock();self.lastMessage=ProcessInfo.processInfo.systemUptime;self.lock.unlock();self.buffer.append(data);if self.buffer.count>1_000_000 {self.fail("矿池消息过大");return}
    while let n=self.buffer.firstIndex(of:10){let line=self.buffer.prefix(upTo:n);self.buffer.removeSubrange(...n);do{try self.handle(line)}catch{self.fail("矿池协议异常：\(error)");return}}
   }
   if let error=error {self.fail("矿池断开：\(error)",retry:true)}
   else if complete {self.fail("矿池已关闭连接",retry:true)}
   else {self.receive()}
  }
 }
 func handle(_ data:Data) throws {
  guard let v=try JSONSerialization.jsonObject(with:data) as? [String:Any] else {throw MinerError.message("无效 JSON")}
  if let id=v["id"] as? Int {
   if id==1 {
    guard let r=v["result"] as? [String:Any],r["protocol"] as? String=="parano1d-stratum-v1",r["nonce_bits"] as? Int==64,let ns=r["session_namespace"] as? String,hexData(ns)?.count==8 else {throw MinerError.message("不支持的矿池协议")}
    lock.lock();namespace=ns;lock.unlock()
    send(["id":2,"method":"mining.authorize","params":[username,"x"]])
   } else if id==2 {
    guard v["result"] as? Bool==true else{throw MinerError.message("钱包未通过矿池认证")}
    lock.lock();authorized=true;lock.unlock();event("钱包认证成功")
   } else if id>=100 {
    if v["result"] as? Bool==true {share(true,false)}
    else {
     let e=v["error"] as? [String:Any];let message=e?["message"] as? String ?? "未知拒绝"
     let stale=message.lowercased().contains("stale") || message.lowercased().contains("superseded")
     share(false,stale);event("份额未接受：\(message)")
     if !stale {throw MinerError.message("份额验证失败，已停止：\(message)")}
    }
   }
  } else if v["method"] as? String=="mining.notify" {
   guard let params=v["params"] as? [[String:Any]],params.count==1,let newJob=PoolJob(params[0]) else{throw MinerError.message("任务格式不支持")}
   lock.lock();let ns=namespace;lock.unlock()
   guard newJob.prefix==ns else{throw MinerError.message("任务 nonce 命名空间不匹配")}
   lock.lock();job=newJob;lock.unlock()
   event("收到新的挖矿任务")
  }
 }
 func current()->(PoolJob?,Bool,Bool){lock.lock();defer{lock.unlock()};return(job,authorized,ended)}
 func submit(_ nonce:UInt64,for old:PoolJob) {
  lock.lock();guard !ended,authorized,job?.id==old.id else {lock.unlock();return};let id=submitID;submitID+=1;lock.unlock()
  let lo=(0..<8).map{String(format:"%02x",(nonce>>($0*8))&255)}.joined()
  send(["id":id,"method":"mining.submit","params":[old.id,lo+old.prefix,old.domain]])
 }
 func failure()->(Bool,String){lock.lock();defer{lock.unlock()};return(retryable,failureReason)}
 func checkDeadline(){lock.lock();let age=ProcessInfo.processInfo.systemUptime-lastMessage,ready=authorized;lock.unlock();if age>(ready ? 180:45){fail(ready ? "矿池 180 秒无消息":"矿池握手超时",retry:true)}}
 func fail(_ message:String,retry:Bool=false){lock.lock();let was=ended;if !was{ended=true;job=nil;retryable=retry;failureReason=message};lock.unlock();if !was {event(message)};connection.cancel()}
 func stop(){lock.lock();ended=true;job=nil;lock.unlock();connection.cancel()}
}
final class MiningWorker {
 let lock=NSLock(),gpu:Bool,directory:URL
 var stopped=false,session:PoolSession?,hasher:HashProcess?,oracle:HashProcess?
 let event:(String)->Void,rate:(Double)->Void,share:(Bool,Bool)->Void,done:()->Void
 let cpuThreads:Int,load:()->(Int,Bool)
 var lastThermal:ProcessInfo.ThermalState?
 init(gpu:Bool,directory:URL,cpuThreads:Int=4,load:@escaping()->(Int,Bool)={ (70,true) },event:@escaping(String)->Void,rate:@escaping(Double)->Void,share:@escaping(Bool,Bool)->Void,done:@escaping()->Void){self.gpu=gpu;self.directory=directory;self.cpuThreads=min(ProcessInfo.processInfo.activeProcessorCount,max(1,cpuThreads));self.load=load;self.event=event;self.rate=rate;self.share=share;self.done=done}
 func isStopped()->Bool{lock.lock();defer{lock.unlock()};return stopped}
 func wait(_ seconds:Double)->Bool {
  let end=ProcessInfo.processInfo.systemUptime+max(0,seconds)
  while !isStopped() && ProcessInfo.processInfo.systemUptime<end {Thread.sleep(forTimeInterval:min(0.05,max(0,end-ProcessInfo.processInfo.systemUptime)))}
  return !isStopped()
 }
 func duty()->Double {
  let (percent,protect)=load(),thermal=ProcessInfo.processInfo.thermalState
  if lastThermal != thermal {lastThermal=thermal;if protect && (thermal == .serious || thermal == .critical){event("系统散热状态：\(LoadPolicy.thermalLabel(thermal))")}else if protect{event("系统散热状态：\(LoadPolicy.thermalLabel(thermal))")}}
  return LoadPolicy.duty(percent:gpu ? percent:100,thermal:thermal,protect:protect)
 }
 func start(wallet:String,worker:String) {
  DispatchQueue.global(qos:.userInitiated).async{[self] in
   defer{stop();done()}
   do {
    let h=try HashProcess(executable:directory.appendingPathComponent(gpu ? "bin/noid-metal":"bin/noid-cpu"),directory:directory,threads:gpu ? 1:cpuThreads)
    let o=gpu ? try HashProcess(executable:directory.appendingPathComponent("bin/noid-cpu"),directory:directory):h
    lock.lock();hasher=h;oracle=o;lock.unlock()
    event(gpu ? "GPU 目标强度 \(load().0)%（计算占空比）":"CPU 使用 \(cpuThreads) 个线程")
    guard !isStopped() else{return}
    if gpu {
     let check:[String:Any]=["header":String(repeating:"00",count:256),"count":16,"base":"4294967290","prefix":"123456789","digests":true]
     let actual=try h.call(check),expected=try o.call(check)
     guard actual["digests"] as? [String]==expected["digests"] as? [String] else{throw MinerError.message("GPU 启动校验不通过")}
     event("GPU / 官方 CPU 启动校验通过")
    }
    var s:PoolSession?,attempt=0,last="",prepared:[String:Any]=[:],base:UInt64=0,hashes=0,lastReport=Date(),started=Date(),sessionStarted=ProcessInfo.processInfo.systemUptime
    while !isStopped() {
     if s == nil {
      let fresh=PoolSession(wallet:wallet,worker:worker,event:event,share:share)
      lock.lock();session=fresh;lock.unlock();if isStopped(){fresh.stop();break}
      fresh.start();s=fresh;sessionStarted=ProcessInfo.processInfo.systemUptime;last="";base=0;prepared=[:];hashes=0;started=Date();lastReport=Date()
     }
     guard let pool=s else{continue};pool.checkDeadline()
     let (candidate,authorized,ended)=pool.current()
     if ended {
      let (retry,reason)=pool.failure();pool.stop();s=nil;rate(0)
      if !retry {throw MinerError.message(reason.isEmpty ? "矿池会话已停止":reason)}
      attempt+=1;let delay=LoadPolicy.retryDelay(attempt);event("临时连接中断，\(Int(delay)) 秒后重连；手动停止可取消")
      if !wait(delay){break};continue
     }
     guard authorized,let job=candidate,job.expires>Date() else{Thread.sleep(forTimeInterval:0.05);continue}
     if ProcessInfo.processInfo.systemUptime-sessionStarted>30 {attempt=0}
     let targetDuty=duty();if targetDuty==0 {rate(0);if !wait(0.25){break};continue}
     let batchStarted=ProcessInfo.processInfo.systemUptime
     if job.id != last {last=job.id;base=0;prepared=gpu ? try o.call(["header":job.header,"prepare":true]):[:]}
     let count=gpu ? 262144:16384
     if base>UInt64.max-UInt64(count){throw MinerError.message("nonce 范围耗尽")}
     var request:[String:Any]=["header":job.header,"count":count,"base":String(base),"prefix":String(job.prefixValue),"target":job.target]
     for (k,v) in prepared {request[k]=v}
     let output=try h.call(request)
     if !gpu,output["threads"] as? Int != cpuThreads {throw MinerError.message("CPU 线程限制未生效")}
     guard let nonces=output["nonces"] as? [String] else{throw MinerError.message("计算输出缺少候选份额")}
     hashes+=count;base+=UInt64(count)
     if Date().timeIntervalSince(lastReport)>2 {rate(Double(hashes)/Date().timeIntervalSince(started));lastReport=Date()}
     if pool.current().0?.id == job.id && job.expires>Date(){for text in nonces {
      guard let nonce=UInt64(text) else{throw MinerError.message("无效 nonce")}
      if gpu {
       let proof=try o.call(["header":job.header,"count":1,"base":text,"prefix":String(job.prefixValue),"target":job.target])
       guard proof["nonces"] as? [String]==[text] else{throw MinerError.message("GPU 候选与官方 CPU 算法不一致")}
      }
      if !isStopped(){pool.submit(nonce,for:job)}
     }}
     let pause=LoadPolicy.pauseSeconds(busy:ProcessInfo.processInfo.systemUptime-batchStarted,duty:targetDuty)
     if !wait(pause){break}
    }
   } catch {if !isStopped(){event("已停止：\(error)")}}
  }
 }
 func stop(){lock.lock();stopped=true;let s=session,h=hasher,o=oracle;lock.unlock();s?.stop();h?.stop();if o !== h{o?.stop()};rate(0)}
}
