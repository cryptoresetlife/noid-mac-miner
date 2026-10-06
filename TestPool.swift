import Foundation
@main struct TestPool {
 static func main() {
  guard CommandLine.arguments.count>1,let address=ProcessInfo.processInfo.environment["NOID_TEST_WALLET"],validWallet(address) else{fputs("Set NOID_TEST_WALLET and supply the packaged miner directory\n",stderr);exit(2)}
  let directory=URL(fileURLWithPath:CommandLine.arguments[1]),lock=NSLock()
  var accepted=[0,0],connections=0,errors=[String](),ended=0,reconnecting=false,rates=[0.0,0.0]
  var workers=[MiningWorker]()
  for index in 0..<2 {
   let worker=MiningWorker(gpu:index==1,directory:directory,cpuThreads:2,load:{(50,false)},event:{message in
    print("\(index==1 ? "GPU":"CPU") \(message)");fflush(stdout)
    lock.lock();if index==1 && message.contains("钱包认证成功"){connections+=1};if message.hasPrefix("已停止："){errors.append(message)};if index==1 && message.contains("秒后重连"){reconnecting=true};lock.unlock()
   },rate:{value in lock.lock();if value>0{rates[index]=value};lock.unlock()},share:{ok,stale in lock.lock();if ok{accepted[index]+=1}else if !stale{errors.append("Non-stale share rejected")};lock.unlock()},done:{lock.lock();ended+=1;lock.unlock()})
   workers.append(worker);worker.start(wallet:address,worker:"mac-v04-test-\(index)-\(UUID().uuidString.prefix(6))")
  }
  var firstDrop=false,secondDrop=false,acceptedBefore=0,manualStop=false,authAtStop=0
  let start=ProcessInfo.processInfo.systemUptime
  while ProcessInfo.processInfo.systemUptime-start<240 {
   lock.lock();let counts=accepted,auths=connections,retry=reconnecting,failed = !errors.isEmpty;lock.unlock()
   if failed {break}
   if !firstDrop && counts.allSatisfy({$0>0}) {
    acceptedBefore=counts[1];workers[1].lock.lock();let pool=workers[1].session;workers[1].lock.unlock()
    pool?.fail("验证：模拟临时断连",retry:true);firstDrop=true
   } else if firstDrop && !secondDrop && auths>=2 && counts[1]>acceptedBefore {
    lock.lock();reconnecting=false;lock.unlock();workers[1].lock.lock();let pool=workers[1].session;workers[1].lock.unlock()
    pool?.fail("验证：重连等待时手动停止",retry:true);secondDrop=true
   } else if secondDrop && retry {
    workers.forEach{$0.stop()};authAtStop=auths;manualStop=true;break
   }
   Thread.sleep(forTimeInterval:0.05)
  }
  workers.forEach{$0.stop()}
  for _ in 0..<40 {lock.lock();let finished=ended==2;lock.unlock();if finished{break};Thread.sleep(forTimeInterval:0.05)}
  Thread.sleep(forTimeInterval:3)
  lock.lock();let success=firstDrop && secondDrop && manualStop && connections==authAtStop && accepted.allSatisfy{$0>0} && errors.isEmpty && ended==2
  let report:[String:Any]=["passed":success,"cpu_threads":2,"gpu_duty_target_percent":50,"accepted":accepted,"gpu_authentications":connections,"cpu_hps":rates[0],"gpu_hps":rates[1],"errors":errors,"workers_ended":ended,"no_reconnect_after_manual_stop":manualStop && connections==authAtStop,"seconds":ProcessInfo.processInfo.systemUptime-start];lock.unlock()
  let data=try! JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]);print(String(decoding:data,as:UTF8.self));try! data.write(to:URL(fileURLWithPath:"pool-v04-validation.json"));exit(success ? 0:1)
 }
}
