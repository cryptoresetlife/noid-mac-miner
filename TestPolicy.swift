import Foundation
@main struct TestPolicy {
 static func main() {
  precondition(LoadPolicy.duty(percent:70,thermal:.nominal,protect:true)==0.7)
  precondition(LoadPolicy.duty(percent:100,thermal:.serious,protect:true)==0.5)
  precondition(LoadPolicy.duty(percent:20,thermal:.serious,protect:true)==0.2)
  precondition(LoadPolicy.duty(percent:50,thermal:.critical,protect:true)==0)
  precondition(LoadPolicy.duty(percent:80,thermal:.critical,protect:false)==0.8)
  precondition(abs(LoadPolicy.pauseSeconds(busy:0.2,duty:0.5)-0.2)<0.0001)
  precondition(LoadPolicy.pauseSeconds(busy:0.2,duty:1)==0)
  precondition((1...8).map{LoadPolicy.retryDelay($0)} == [2,4,8,16,30,30,30,30])
  let worker=MiningWorker(gpu:true,directory:URL(fileURLWithPath:"."),event:{_ in},rate:{_ in},share:{_,_ in},done:{})
  let done=DispatchSemaphore(value:0)
  DispatchQueue.global().async{precondition(!worker.wait(30));done.signal()}
  Thread.sleep(forTimeInterval:0.1);let start=ProcessInfo.processInfo.systemUptime;worker.stop()
  precondition(done.wait(timeout:.now()+1) == .success)
  precondition(ProcessInfo.processInfo.systemUptime-start<0.2)
  let session=PoolSession(wallet:"test",worker:"test",event:{_ in},share:{_,_ in})
  session.fail("test transport failure",retry:true)
  session.fail("late failure",retry:false)
  precondition(session.failure().0 && session.failure().1=="test transport failure")
  let fatal=PoolSession(wallet:"test",worker:"test",event:{_ in},share:{_,_ in})
  fatal.fail("test protocol error");precondition(!fatal.failure().0)
  let timeout=PoolSession(wallet:"test",worker:"test",event:{_ in},share:{_,_ in})
  timeout.lastMessage=ProcessInfo.processInfo.systemUptime-46;timeout.checkDeadline();precondition(timeout.current().2 && timeout.failure().0)
  print("Load limits, thermal policy, backoff, fatal errors, handshake deadline and stop cancellation passed")
 }
}
