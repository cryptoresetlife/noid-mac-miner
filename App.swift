import SwiftUI
import AppKit

enum MiningMode:String,CaseIterable,Identifiable {
 case cpu="CPU",gpu="GPU",both="CPU + GPU"
 var id:String {rawValue}
}
final class WorkerLoad {
 private let lock=NSLock()
 private var percent=70,protect=true
 func set(_ value:Int,_ enabled:Bool){lock.lock();percent=min(100,max(10,value));protect=enabled;lock.unlock()}
 func get()->(Int,Bool){lock.lock();defer{lock.unlock()};return(percent,protect)}
}
final class MiningModel:ObservableObject {
 @Published var wallet=UserDefaults.standard.string(forKey:"wallet") ?? ""
 @Published var mode:MiningMode = .gpu
 @Published var running=false
 @Published var cpuRate=0.0
 @Published var gpuRate=0.0
 @Published var accepted=0
 @Published var rejected=0
 @Published var stale=0
 @Published var logs:[String]=[]
 @Published var cpuThreads=max(1,min(ProcessInfo.processInfo.activeProcessorCount,UserDefaults.standard.object(forKey:"cpuThreads") as? Int ?? 4))
 @Published var gpuIntensity=Double(min(100,max(10,UserDefaults.standard.object(forKey:"gpuIntensity") as? Int ?? 70)))
 @Published var thermalProtection=UserDefaults.standard.object(forKey:"thermalProtection") as? Bool ?? true
 @Published var stopReason=""
 @Published var thermalState=LoadPolicy.thermalLabel(ProcessInfo.processInfo.thermalState)
 @Published var endedBackends=0
 let load=WorkerLoad()
 let maxThreads=ProcessInfo.processInfo.activeProcessorCount
 var workers:[MiningWorker]=[]
 var remaining=0
 let directory:URL
 init(directory:URL){self.directory=directory}
 func updateLoad(){load.set(Int(gpuIntensity),thermalProtection);UserDefaults.standard.set(cpuThreads,forKey:"cpuThreads");UserDefaults.standard.set(Int(gpuIntensity),forKey:"gpuIntensity");UserDefaults.standard.set(thermalProtection,forKey:"thermalProtection")}
 func exportLogs(){
  let panel=NSSavePanel();panel.nameFieldStringValue="NOID-Miner-log.txt"
  guard panel.runModal() == .OK,let url=panel.url else{return}
  let safe=logs.map{$0.replacingOccurrences(of:"o1[qpzry9x8gf2tvdw0s3jn54khce6mua7l]{12,88}",with:"[钱包已隐藏]",options:.regularExpression)}
  let text="NOID Miner 0.4.0\nCPU threads: \(cpuThreads), GPU duty target: \(Int(gpuIntensity))%, thermal protection: \(thermalProtection)\n"+safe.joined(separator:"\n")+"\n"
  do{try text.write(to:url,atomically:true,encoding:.utf8)}catch{log("日志保存失败：\(error.localizedDescription)")}
 }
 func log(_ message:String){DispatchQueue.main.async{[weak self] in guard let self=self else{return};self.logs.append(Date().formatted(date:.omitted,time:.standard)+"  "+message);if self.logs.count>150 {self.logs.removeFirst(self.logs.count-150)}}}
 func start(){
  let address=wallet.trimmingCharacters(in:.whitespacesAndNewlines)
  guard !running else{return}
  guard validWallet(address) else{log("请输入有效的 NOID 钱包地址（o1 开头，校验码须正确）");return}
  wallet=address;UserDefaults.standard.set(address,forKey:"wallet")
  updateLoad();running=true;accepted=0;rejected=0;stale=0;cpuRate=0;gpuRate=0;workers=[];stopReason="";endedBackends=0
  let backends = mode == .both ? [false,true]:[mode == .gpu]
  remaining=backends.count
  let suffix=String(UUID().uuidString.prefix(8)).lowercased()
  for gpu in backends {
   let label=gpu ? "GPU":"CPU"
   let w=MiningWorker(gpu:gpu,directory:directory,cpuThreads:cpuThreads,load:{[load] in load.get()},event:{[weak self] message in self?.log(label+" · "+message);if message.hasPrefix("已停止："){DispatchQueue.main.async{self?.stopReason=label+" · "+message}}},rate:{[weak self] rate in DispatchQueue.main.async{if gpu{self?.gpuRate=rate}else{self?.cpuRate=rate}}},share:{[weak self] ok,old in DispatchQueue.main.async{guard let self=self else{return};if ok{self.accepted+=1;self.log(label+" · 矿池已接受份额")}else if old{self.stale+=1}else{self.rejected+=1}}},done:{[weak self] in DispatchQueue.main.async{guard let self=self else{return};self.remaining-=1;self.endedBackends+=1;self.log(label+" · 计算进程已结束");if self.remaining<=0{self.running=false;self.workers=[];self.log("全部矿工已停止")}}})
   workers.append(w);w.start(wallet:address,worker:"mac-\(suffix)-\(gpu ? "gpu":"cpu")")
  }
  log("开始 \(mode.rawValue) · InnovLab / PPLNS · 收款地址 \(address)")
 }
 func stop(){guard running else{return};log("正在停止…");workers.forEach{$0.stop()}}
 func rate(_ value:Double)->String {if value>=1_000_000{return String(format:"%.2f MH/s",value/1_000_000)};if value>=1000{return String(format:"%.1f KH/s",value/1000)};return String(format:"%.0f H/s",value)}
}
struct ContentView:View {
 @ObservedObject var model:MiningModel
 var body:some View {
  VStack(alignment:.leading,spacing:18){
   HStack{VStack(alignment:.leading){Text("NOID Miner").font(.largeTitle.bold());Text("Apple Silicon · InnovLab 矿池").foregroundStyle(.secondary)};Spacer();Text(model.running ? (model.endedBackends>0 ? "部分运行":"运行中"):"已停止").foregroundStyle(model.running ? .green:.secondary)}
   Text("收款钱包").font(.headline)
   TextField("输入你的 NOID 钱包地址（o1…）",text:$model.wallet).textFieldStyle(.roundedBorder).disabled(model.running)
   Picker("计算设备",selection:$model.mode){ForEach(MiningMode.allCases){Text($0.rawValue).tag($0)}}.pickerStyle(.segmented).disabled(model.running)
   HStack(spacing:24){
    Stepper("CPU 线程：\(model.cpuThreads) / \(model.maxThreads)",value:$model.cpuThreads,in:1...model.maxThreads).disabled(model.running || model.mode == .gpu)
    Text("CPU 线程需停止后调整").font(.caption).foregroundStyle(.secondary)
   }
   HStack{Text("GPU 强度：\(Int(model.gpuIntensity))%").frame(width:135,alignment:.leading);Slider(value:$model.gpuIntensity,in:10...100,step:5).disabled(model.mode == .cpu);Text("10–100%").font(.caption).foregroundStyle(.secondary)}
   HStack{Toggle("系统过热自动降载",isOn:$model.thermalProtection);Spacer();Text("散热：\(model.thermalState)").font(.caption).foregroundStyle(.secondary)}
   Text("GPU 强度为目标计算占空比，可运行中调整；不是功耗上限，实际占用率会波动。").font(.caption).foregroundStyle(.secondary)
   HStack{Button("开始挖矿"){model.start()}.buttonStyle(.borderedProminent).disabled(model.running);Button("停止挖矿"){model.stop()}.disabled(!model.running);Spacer();Text("退出程序会停止挖矿").foregroundStyle(.secondary).font(.caption)}
   Divider()
   HStack(spacing:30){metric("CPU 算力",model.rate(model.cpuRate));metric("GPU 算力",model.rate(model.gpuRate));metric("合计算力",model.rate(model.cpuRate+model.gpuRate))}
   HStack(spacing:30){metric("接受份额",String(model.accepted));metric("拒绝份额",String(model.rejected));metric("过期份额",String(model.stale))}
   Text("份额表示矿池接受了工作量，实际收益按矿池 PPLNS 规则结算。").font(.caption).foregroundStyle(.secondary)
   if !model.stopReason.isEmpty{Text(model.stopReason).font(.caption).foregroundStyle(.red).textSelection(.enabled)}
   ScrollViewReader{proxy in ScrollView{LazyVStack(alignment:.leading,spacing:5){ForEach(Array(model.logs.enumerated()),id:\.offset){i,line in Text(line).font(.system(size:11,design:.monospaced)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading).id(i)}}.padding(10)}.background(Color.black.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius:8)).onChange(of:model.logs.count){_ in if let last=model.logs.indices.last {proxy.scrollTo(last,anchor:.bottom)}}}
   HStack{Text("实验版 0.4 · 无私钥输入 · 不随开机自动启动").font(.caption2).foregroundStyle(.secondary);Spacer();Button("导出诊断日志"){model.exportLogs()}.font(.caption)}
  }.padding(24).frame(minWidth:780,minHeight:730)
   .onChange(of:model.gpuIntensity){_ in model.updateLoad()}
   .onChange(of:model.thermalProtection){_ in model.updateLoad()}
   .onReceive(Timer.publish(every:1,on:.main,in:.common).autoconnect()){_ in model.thermalState=LoadPolicy.thermalLabel(ProcessInfo.processInfo.thermalState)}
 }
 func metric(_ title:String,_ value:String)->some View {VStack(alignment:.leading,spacing:5){Text(title).font(.caption).foregroundStyle(.secondary);Text(value).font(.title3.monospacedDigit().bold())}.frame(maxWidth:.infinity,alignment:.leading)}
}
final class AppDelegate:NSObject,NSApplicationDelegate {
 var model:MiningModel?
 var didResume=false
 func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool{true}
 func applicationWillTerminate(_ notification:Notification){model?.stop()}
}
#if !PREVIEW
@main struct NOIDApp:App {
 @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
 @StateObject var model:MiningModel
 init(){
  let directory=Bundle.main.resourceURL!.appendingPathComponent("miner")
  _model=StateObject(wrappedValue:MiningModel(directory:directory))
 }
 var body:some Scene{WindowGroup{ContentView(model:model).onAppear{
  delegate.model=model
  if !delegate.didResume && CommandLine.arguments.contains("--resume-both") {
   delegate.didResume=true;model.mode = .both;model.start()
  }
 }}.windowStyle(.titleBar)}
}
#endif
