import Foundation
import CryptoKit
import AVFoundation

enum AudioFiles {
    static func convert(_ source:URL,to destination:URL)throws {
        let input=try AVAudioFile(forReading:source),format=input.processingFormat
        let output=try AVAudioFile(forWriting:destination,settings:format.settings,commonFormat:format.commonFormat,interleaved:format.isInterleaved)
        guard let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:8192)else{throw AppError.message("无法创建音频转换缓冲区。")}
        while input.framePosition<input.length {try input.read(into:buffer);if buffer.frameLength==0{break};try output.write(from:buffer)}
    }
    static func repairInterruptedWAV(_ url:URL)throws {
        let handle=try FileHandle(forUpdating:url);defer{try? handle.close()}
        let length=try handle.seekToEnd();try handle.seek(toOffset:0)
        guard length>44,length<UInt64(UInt32.max),let header=try handle.read(upToCount:4096),header.count>=44,
              String(data:header[0..<4],encoding:.ascii)=="RIFF",String(data:header[8..<12],encoding:.ascii)=="WAVE" else{return}
        func uint32(_ position:Int)->UInt32{header[position..<position+4].enumerated().reduce(UInt32(0)){$0|UInt32($1.element)<<(UInt32($1.offset)*8)}}
        func write(_ value:UInt32,at offset:Int)throws{var little=value.littleEndian;try handle.seek(toOffset:UInt64(offset));try withUnsafeBytes(of:&little){try handle.write(contentsOf:$0)}}
        var offset=12,dataOffset:Int?,factOffset:Int?,alignment=1
        while offset+8<=header.count {
            let tag=String(data:header[offset..<offset+4],encoding:.ascii),size=Int(uint32(offset+4))
            if tag=="fmt ",offset+22<=header.count{alignment=Int(header[offset+20])|Int(header[offset+21])<<8}
            if tag=="fact"{factOffset=offset+8}
            if tag=="data"{dataOffset=offset;break}
            guard size>0,offset+8+size>offset else{break};offset+=8+size+(size%2)
        }
        guard let dataOffset,length>UInt64(dataOffset+8),alignment>0 else{return}
        let size=UInt32(length-UInt64(dataOffset+8))
        if uint32(dataOffset+4) != size{try write(size,at:dataOffset+4);if let factOffset{try write(size/UInt32(alignment),at:factOffset)}}
        if uint32(4) != UInt32(length-8){try write(UInt32(length-8),at:4)}
        try handle.synchronize()
    }
}
struct ModelFile:Codable{let path:String;let bytes:Int64;let sha256:String}
enum ModelResources {
    static func manifest()throws->[String:[ModelFile]] {
        guard let path=Bundle.main.url(forResource:"ModelManifest",withExtension:"json")else{throw AppError.message("缺少模型校验清单，请重新安装应用。")}
        return try JSONDecoder().decode([String:[ModelFile]].self,from:Data(contentsOf:path))
    }
    static func sha256(_ url:URL)throws->String {
        let file=try FileHandle(forReadingFrom:url);defer{try? file.close()};var hasher=SHA256()
        while let data=try file.read(upToCount:1_048_576),!data.isEmpty{hasher.update(data:data)}
        return hasher.finalize().map{String(format:"%02x",$0)}.joined()
    }
    static func validatePath(_ path:String)throws{
        guard !path.isEmpty,!path.hasPrefix("/"),!path.split(separator:"/").contains(".."),!path.contains("\\")else{throw AppError.message("模型文件路径无效。")}
    }
    static func validate(_ root:URL,manifest:[String:[ModelFile]])throws {
        for (model,files)in manifest{for file in files{
            try validatePath(model);try validatePath(file.path)
            let path=root.appendingPathComponent(model).appendingPathComponent(file.path)
            let bytes=(try FileManager.default.attributesOfItem(atPath:path.path)[.size]as?NSNumber)?.int64Value
            guard bytes==file.bytes,try sha256(path)==file.sha256 else{throw AppError.message("模型文件不完整或版本不符：\(model)/\(file.path)")}
        }}
    }
    static func installModel(from source:URL,name:String,files:[ModelFile])throws {
        try validatePath(name)
        // Validation happens off the UI thread before this bounded atomic swap.
        guard !files.isEmpty,files.allSatisfy({((try? FileManager.default.attributesOfItem(atPath:source.appendingPathComponent($0.path).path)[.size])as?NSNumber)?.int64Value==$0.bytes})else{throw AppError.message("模型暂存文件不完整。")}
        try FileManager.default.createDirectory(at:AppPaths.models,withIntermediateDirectories:true)
        let target=AppPaths.models.appendingPathComponent(name),backup=AppPaths.root.appendingPathComponent("ModelBackup-"+UUID().uuidString)
        let existed=FileManager.default.fileExists(atPath:target.path)
        if existed{try FileManager.default.moveItem(at:target,to:backup)}
        do{try FileManager.default.moveItem(at:source,to:target)}catch{if existed{try? FileManager.default.moveItem(at:backup,to:target)};throw error}
    }
    static func importModels(from source:URL,manifest:[String:[ModelFile]])throws {
        let selected=manifest.filter{FileManager.default.fileExists(atPath:source.appendingPathComponent($0.key).path)}
        guard !selected.isEmpty else{throw AppError.message("请选择包含识别、整理或翻译模型子文件夹的目录。")}
        try validate(source,manifest:selected)
        let stage=AppPaths.root.appendingPathComponent("ModelImport-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:stage,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:stage)}
        for (name,files)in selected{
            for file in files{
                let target=stage.appendingPathComponent(name).appendingPathComponent(file.path)
                try FileManager.default.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
                try FileManager.default.copyItem(at:source.appendingPathComponent(name).appendingPathComponent(file.path).resolvingSymlinksInPath(),to:target)
            }
        }
        try validate(stage,manifest:selected)
        for (name,files)in selected{try installModel(from:stage.appendingPathComponent(name),name:name,files:files)}
    }
}
