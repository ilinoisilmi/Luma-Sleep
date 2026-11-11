import Foundation
import AVFoundation
import Accelerate
import Combine

/// Event-only default: audio buffers are reduced to level statistics in memory, never uploaded.
/// Retention writes one bounded recording, not automatically classified snore clips.
@MainActor final class AudioMonitor:ObservableObject {
    @Published private(set) var isRunning=false
    @Published private(set) var status="Sound monitoring is off"
    private weak var store:AppStore?
    private let engine=AVAudioEngine()
    private var processor:LevelProcessor?
    private var sessionID:UUID?
    private var interruption: NSObjectProtocol?
    private var routeChange:NSObjectProtocol?
    private var mediaReset:NSObjectProtocol?
    private var tapInstalled=false
    init(store:AppStore) { self.store=store }
    var folder:URL { AppStore.dataDirectory.appendingPathComponent("Audio",isDirectory:true) }
    func start(retain:Bool) async throws {
        guard let store, !store.isDemo else { throw LumaError.unavailable("Microphone use is disabled in demo mode.") }
        guard !isRunning else { return }
        let allowed=await withCheckedContinuation { continuation in AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning:$0) } }
        guard allowed else { throw LumaError.unavailable("Microphone permission is off. Enable it in iPhone Settings to monitor sound events.") }
        let session=AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord,mode:.measurement,options:[.defaultToSpeaker,.mixWithOthers])
        try session.setActive(true)
        let input=engine.inputNode, format=input.outputFormat(forBus:0)
        guard format.sampleRate>0,format.channelCount>0 else { try? session.setActive(false); throw LumaError.unavailable("No microphone input is available.") }
        var metadata=AudioSession(start:store.now); metadata.retainsAudio=retain
        var file:AVAudioFile?
        do {
            if retain {
                try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true,attributes:[.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication])
                var folderURL=folder; var resource=URLResourceValues(); resource.isExcludedFromBackup=true; try folderURL.setResourceValues(resource)
                let filename=metadata.id.uuidString+".m4a", url=folder.appendingPathComponent(filename)
                let capacity=try folder.resourceValues(forKeys:[.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
                guard capacity>500*1024*1024 else { throw LumaError.unavailable("Free at least 500 MB before retaining a recording. Event-only mode does not keep raw audio.") }
                file=try AVAudioFile(forWriting:url,settings:[AVFormatIDKey:kAudioFormatMPEG4AAC,AVSampleRateKey:format.sampleRate,AVNumberOfChannelsKey:format.channelCount,AVEncoderBitRateKey:64000])
                try FileManager.default.setAttributes([.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication],ofItemAtPath:url.path)
                metadata.fileName=filename
            }
            try store.transact{$0.audioSessions.append(metadata)}
            sessionID=metadata.id
            let p=LevelProcessor(sampleRate:format.sampleRate,file:file) { [weak self] events,reason in
                Task { @MainActor in self?.receive(events:events,stopReason:reason) }
            }
            processor=p
            input.installTap(onBus:0,bufferSize:4096,format:format) { buffer,_ in p.consume(buffer) }
            tapInstalled=true; engine.prepare(); try engine.start(); isRunning=true; status="Listening for sound events"
            interruption=NotificationCenter.default.addObserver(forName:AVAudioSession.interruptionNotification,object:nil,queue:.main) { [weak self] notification in
                guard let raw=notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt, raw == AVAudioSession.InterruptionType.began.rawValue else { return }
                Task { @MainActor in self?.stop(reason:"Interrupted; start again when ready") }
            }
            routeChange=NotificationCenter.default.addObserver(forName:AVAudioSession.routeChangeNotification,object:nil,queue:.main) { [weak self] _ in
                Task { @MainActor in self?.stop(reason:"Audio route changed; review and restart") }
            }
            mediaReset=NotificationCenter.default.addObserver(forName:AVAudioSession.mediaServicesWereResetNotification,object:nil,queue:.main) { [weak self] _ in
                Task { @MainActor in self?.stop(reason:"Audio system reset; review and restart") }
            }
        } catch {
            stop(reason:"Could not start recording")
            try? session.setActive(false,options:.notifyOthersOnDeactivation)
            throw error
        }
    }
    private func receive(events:[SoundEvent],stopReason:String?) {
        guard let store, let id=sessionID else { return }
        do { try store.transact { s in if let i=s.audioSessions.firstIndex(where:{$0.id == id}) { s.audioSessions[i].events.append(contentsOf:events) } } }
        catch { stop(reason:"Storage error; recording stopped"); store.message="Sound metadata could not be saved. \(error.localizedDescription)"; return }
        if let stopReason { stop(reason:stopReason) }
    }
    func stop(reason:String="Stopped") {
        if tapInstalled { engine.inputNode.removeTap(onBus:0); tapInstalled=false }
        engine.stop()
        let pending=processor?.finish() ?? []; processor=nil
        for observer in [interruption,routeChange,mediaReset].compactMap({$0}) { NotificationCenter.default.removeObserver(observer) }
        interruption=nil; routeChange=nil; mediaReset=nil
        try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)
        if let store,let id=sessionID {
            store.perform { try store.transact { s in if let i=s.audioSessions.firstIndex(where:{$0.id == id}) { s.audioSessions[i].end=store.now; s.audioSessions[i].status=reason; s.audioSessions[i].events.append(contentsOf:pending) } } }
        }
        sessionID=nil; isRunning=false; status=reason
    }
    func deleteRecording(_ id:UUID) throws {
        guard let store else { return }
        if sessionID == id { stop(reason:"Stopped before deletion") }
        if let session=store.data.audioSessions.first(where:{$0.id == id}), let name=session.fileName {
            let url=folder.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath:url.path) { try FileManager.default.removeItem(at:url) }
        }
        try store.transact { s in if let i=s.audioSessions.firstIndex(where:{$0.id == id}) { s.audioSessions[i].fileName=nil; s.audioSessions[i].events=[]; s.audioSessions[i].status="Recording and events deleted" } }
    }
    func prune() {
        guard let store,!store.isDemo else { return }
        let cutoff=store.now.addingTimeInterval(-Double(store.data.preferences.audioRetentionDays)*86400)
        for item in store.data.audioSessions where item.end != nil && item.start < cutoff && item.fileName != nil {
            // Keep event summaries; only retained raw recordings expire.
            if let name=item.fileName {
                do {
                    let url=folder.appendingPathComponent(name)
                    if FileManager.default.fileExists(atPath:url.path) { try FileManager.default.removeItem(at:url) }
                    try store.transact { s in if let i=s.audioSessions.firstIndex(where:{$0.id == item.id}) { s.audioSessions[i].fileName=nil } }
                } catch { store.message="Audio cleanup could not finish. \(error.localizedDescription)"; return }
            }
        }
    }
}
/// Audio callback work is serialized here. Only bounded event summaries leave this object.
private final class LevelProcessor:@unchecked Sendable {
    private let lock=NSLock()
    private var file:AVAudioFile?
    private var running=true
    private let sampleRate:Double
    private var accumulatedFrames=0
    private var totalFrames=0
    private var peak:Float = -160
    private var secondCounter=0
    private var currentEventStart:Date?
    private var currentEventPeak:Float = -160
    private var events:[SoundEvent]=[]
    private let callback:([SoundEvent],String?)->Void
    init(sampleRate:Double,file:AVAudioFile?,callback:@escaping([SoundEvent],String?)->Void) { self.sampleRate=sampleRate; self.file=file; self.callback=callback }
    func consume(_ buffer:AVAudioPCMBuffer) {
        lock.lock(); defer{lock.unlock()}
        guard running,let channel=buffer.floatChannelData?.pointee else { return }
        let frames=Int(buffer.frameLength)
        if let file {
            do { try file.write(from:buffer) }
            catch { running=false; self.file=nil; callback(events,"Audio write failed; recording stopped"); events=[]; return }
        }
        var rms:Float=0; vDSP_rmsqv(channel,1,&rms,vDSP_Length(frames))
        let db=20*log10(max(rms,0.00000001)); peak=max(peak,db)
        accumulatedFrames+=frames; totalFrames+=frames
        if Double(accumulatedFrames)>=sampleRate {
            let now=Date()
            if peak > -32 { if currentEventStart == nil { currentEventStart=now }; currentEventPeak=max(currentEventPeak,peak) }
            else if let start=currentEventStart {
                if now.timeIntervalSince(start)>=2 { events.append(SoundEvent(date:start,duration:now.timeIntervalSince(start),peakDB:currentEventPeak)) }
                currentEventStart=nil; currentEventPeak = -160
            }
            accumulatedFrames=0; peak = -160; secondCounter+=1
            if secondCounter>=30 {
                if let file, let resources=try? file.url.resourceValues(forKeys:[.fileSizeKey]), let size=resources.fileSize, size >= 400*1024*1024 {
                    running=false; callback(events,"Reached 400 MB recording limit"); events=[]; return
                }
                callback(events,nil); events=[]; secondCounter=0
            }
        }
        // Bound continuous operation. A retained file is also checked every 30 seconds.
        let limit:Double=12*3600
        if Double(totalFrames)/sampleRate>=limit { running=false; callback(events,"Reached session duration limit"); events=[] }
    }
    func finish()->[SoundEvent] {
        lock.lock(); defer{lock.unlock()}; running=false; file=nil
        if let start=currentEventStart,Date().timeIntervalSince(start)>=2 { events.append(SoundEvent(date:start,duration:Date().timeIntervalSince(start),peakDB:currentEventPeak)) }
        let result=events; events=[]; currentEventStart=nil; return result
    }
}
