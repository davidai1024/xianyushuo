import Foundation

/// Shared audio target; metering never invalidates the whole SwiftUI window.
final class WaveformSignal {
    private let lock=NSLock()
    private var values=[Double](repeating:0,count:34)
    private var received=ProcessInfo.processInfo.systemUptime
    func update(_ next:[Double]){lock.withLock{values=next;received=ProcessInfo.processInfo.systemUptime}}
    func snapshot(now:Double)->[Double]{lock.withLock{now-received>0.35 ? values.map{_ in 0}:values}}
    func reset(){update(Array(repeating:0,count:34))}
}
struct WaveformEnvelope {
    private(set) var values=[Double](repeating:0,count:34)
    mutating func advance(target:[Double],dt:Double){
        for i in values.indices {
            let a=target.indices.contains(max(0,i-1)) ? target[max(0,i-1)]:0
            let b=target.indices.contains(i) ? target[i]:0
            let c=target.indices.contains(min(33,i+1)) ? target[min(33,i+1)]:0
            let goal=max(0,min(1,(a+b*2+c)/4))
            let tau=goal>values[i] ? 0.045:0.16
            let alpha=1-exp(-max(0,min(dt,0.10))/tau)
            values[i]+=(goal-values[i])*alpha
        }
    }
    static func intensity(amplitude:Double,distance:Double)->Double{
        let x=max(0,min(1,(amplitude-distance+0.22)/0.44))
        return x*x*(3-2*x)
    }
}

/// Visual-only contrast mapping for the capsule's existing log-scale meter.
/// Recording samples and ASR gain are unchanged; avoid applying two roots.
enum CapsuleVisualResponse {
    static func level(_ values:[Double])->Double{
        let levels=values.filter{$0.isFinite}.map{min(1,max(0,$0))}.sorted()
        guard !levels.isEmpty else{return 0}
        let mean=levels.reduce(0,+)/Double(levels.count),peak=levels[min(levels.count-1,Int(Double(levels.count)*0.9))]
        let normalized=min(1,max(0,(mean*0.65+peak*0.35-0.065)/0.55))
        return pow(normalized,0.58)
    }
}

/// Roughly 280 ms of real microphone energy. No clock-generated speech pattern.
/// The newest column responds each frame; older syllables move toward the left.
struct CapsuleVoiceHistory {
    private(set) var columns=[Double](repeating:0,count:9)
    private var current=0.0,accumulator=0.0
    mutating func advance(level:Double,dt:Double){
        let target=level.isFinite ? min(1,max(0,level)):0
        let delta=dt.isFinite ? min(0.05,max(0,dt)):0
        let tau=target>current ? 0.025:0.045
        current+=(target-current)*(1-exp(-delta/tau))
        accumulator+=delta
        while accumulator>=0.035{columns.removeFirst();columns.append(current);accumulator-=0.035}
        columns[columns.count-1]=current
    }
}
