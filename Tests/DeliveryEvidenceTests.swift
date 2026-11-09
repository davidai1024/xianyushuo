import Foundation

@main struct DeliveryEvidenceTests {
    static func main(){
        var count=0
        func check(_ value:Bool,_ label:String){precondition(value,label);count+=1}
        check(DeliveryEvidence.expected(before:"abc",range:CFRange(location:1,length:0),inserted:"X")=="aXbc","Insert at cursor preserves surrounding text")
        check(DeliveryEvidence.expected(before:"abc",range:CFRange(location:1,length:1),inserted:"X")=="aXc","Selection replaced once")
        check(DeliveryEvidence.expected(before:"A🙂B",range:CFRange(location:1,length:2),inserted:"输入")=="A输入B","AX ranges use UTF16, not Swift character offsets")
        check(DeliveryEvidence.expected(before:"",range:CFRange(location:0,length:0),inserted:"theft")=="theft","Empty web input expected value")
        check(DeliveryEvidence.expected(before:nil,range:CFRange(location:0,length:0),inserted:"a")==nil,"Unreadable value cannot be verified")
        check(DeliveryEvidence.expected(before:"a",range:nil,inserted:"b")==nil,"Unknown cursor cannot fabricate verification")
        check(DeliveryEvidence.expected(before:"a",range:CFRange(location:2,length:0),inserted:"b")==nil,"Out-of-range cursor rejected")
        check(DeliveryEvidence.expected(before:"a",range:CFRange(location:0,length:2),inserted:"b")==nil,"Out-of-range selection rejected")
        check(DeliveryEvidence.expected(before:"a",range:CFRange(location:-1,length:1),inserted:"b")==nil,"Negative range rejected")
        check(DeliveryEvidence.equivalent("a\r\nb","a\nb"),"Editor line-ending normalization accepted")
        check(!DeliveryEvidence.equivalent("old","old新"),"Setter success with unchanged value cannot verify")
        check(!DeliveryEvidence.equivalent(" new ","new"),"No trimming that hides dropped whitespace")
        check(DeliveryEvidence.verification(before:"\n\n",observed:"写入验证\n",inserted:"写入验证",expected:"写入验证\n\n",webPaste:true)=="new_inserted_text_observed","Web paragraph terminator does not create a false pending state")
        check(DeliveryEvidence.verification(before:"旧草稿",observed:"新内容",inserted:"新内容",expected:"新内容旧草稿",webPaste:true)=="new_inserted_text_observed","Keyboard paste readback can confirm new text despite stale AX selection")
        check(DeliveryEvidence.verification(before:"新内容",observed:"新内容\n",inserted:"新内容",expected:nil,webPaste:true)==nil,"Existing identical text cannot fabricate insertion evidence")
        check(DeliveryEvidence.verification(before:"旧内容",observed:"旧内容",inserted:"新内容",expected:nil,webPaste:true)==nil,"No-op web write remains unverified")
        check(DeliveryEvidence.verification(before:"旧内容",observed:"新内容",inserted:"新内容",expected:nil,webPaste:false)==nil,"AX setter cannot use the relaxed web-paste evidence")
        func probe(_ values:[String?],before:String="旧草稿",inserted:String="新内容",expected:String?="新内容旧草稿",web:Bool=true)->[Bool]{
            var probe=DeliveryReadbackProbe()
            return values.map{probe.observe($0,before:before,inserted:inserted,expected:expected,webPaste:web)}
        }
        check(probe(["旧草稿","旧草稿","旧草稿","新内容","新内容"]) == [false,false,false,false,true],"Delayed editor readback after old 250ms window is confirmed")
        check(probe([nil,nil,"新内容","新内容"]) == [false,false,false,true],"Temporary unreadable AX value can recover without another paste")
        check(probe(["新内容",nil,"新内容","新内容"]) == [false,false,false,true],"Lost focus cannot count as the second stable observation")
        check(probe(["新内容","新内容变了","新内容变了"]) == [false,false,true],"Two different editor values do not make a stable pair")
        check(!probe(Array(repeating:"旧草稿",count:9)).contains(true),"No-op writes never report filled")
        check(!probe(Array(repeating:nil,count:9)).contains(true),"Missing focused input never reports filled")
        check(!probe(["新内容","新内容"],before:"新内容",expected:nil).contains(true),"Pre-existing identical text cannot confirm a paste")
        check(!probe(["新内","新内"]).contains(true),"Partial insert cannot confirm full delivery")
        check(!probe(["新内容","新内容"],web:false).contains(true),"Native setter readback still requires exact expected context")
        check(probe(["新内容旧草稿","新内容旧草稿"],web:false)==[false,true],"Native exact insertion confirms early")
        check(probe(["新内容旧草稿","新内容旧草稿\n"]) == [false,false],"Changing paragraph terminator waits for settlement")
        check(DeliveryReadbackProbe.pauses.reduce(0,+)==1_800_000_000,"Readback has a bounded 1.8s worst-case window")
        check(DeliveryReadbackProbe.pauses.prefix(2).reduce(0,+)<250_000_000,"Fast successful inputs confirm sooner than the old window")
        check(DeliveryReadbackProbe.pauses.first==0,"Readback starts immediately after the one write")
        check(DeliveryReadbackProbe.pauses.prefix(2).reduce(0,+)==35_000_000,"Immediate exact value still needs a separate stable observation")
        for settable in [false,true]{
            check(DeliveryWritePlan.choose(keepClipboard:true,clipboardUnchanged:true,eventPostingAllowed:true,selectedTextSettable:settable) == .keyboardPaste,"Normal paste is first even when an editor claims a settable AX field")
        }
        check(DeliveryWritePlan.choose(keepClipboard:false,clipboardUnchanged:true,eventPostingAllowed:true,selectedTextSettable:true) == .selectedText,"No clipboard permission keeps native insertion")
        check(DeliveryWritePlan.choose(keepClipboard:true,clipboardUnchanged:false,eventPostingAllowed:true,selectedTextSettable:true) == .selectedText,"A newly copied item is never overwritten for paste")
        check(DeliveryWritePlan.choose(keepClipboard:true,clipboardUnchanged:true,eventPostingAllowed:false,selectedTextSettable:true) == .selectedText,"No synthetic event is attempted without existing permission")
        check(DeliveryWritePlan.choose(keepClipboard:false,clipboardUnchanged:false,eventPostingAllowed:false,selectedTextSettable:false) == .unsupported,"Unsupported insertion retains the result")
        check(DeliveryTargetPolicy.mayAcquire(hadInput:false,currentInput:true,external:true),"User focuses editor while recognition is running")
        check(!DeliveryTargetPolicy.mayAcquire(hadInput:true,currentInput:true,external:true),"An established target never silently moves")
        check(!DeliveryTargetPolicy.mayAcquire(hadInput:false,currentInput:false,external:true),"No cursor is not guessed")
        check(!DeliveryTargetPolicy.mayAcquire(hadInput:false,currentInput:true,external:false),"Own settings are not a delivery destination")
        for state in ["clipboard","saved"]{check(DeliveryTargetPolicy.mayWait(reason:"input_not_focused",state:state,autoPaste:true),"Durable missing-focus results can await cursor")}
        for reason in ["input_missing_or_changed","write_sent_but_unverified","auto_paste_disabled","paste_precondition_changed","no_supported_write_method","wechat_context_changed","wechat_context_changed_before_post","wechat_paste_unavailable"]{
            check(!DeliveryTargetPolicy.mayWait(reason:reason,state:"clipboard",autoPaste:true),"Never arm speculative retry after a changed target or write")
        }
        for state in ["verified","unverified","empty"]{check(!DeliveryTargetPolicy.mayWait(reason:"input_not_focused",state:state,autoPaste:true),"Only untouched saved results can await focus")}
        check(!DeliveryTargetPolicy.mayWait(reason:"input_not_focused",state:"clipboard",autoPaste:false),"Auto insertion switch respected")
        let id=UUID()
        let counters:[UInt32]=[9,8,7,6,5]
        let context=WeChatPasteContext(pid:101,windowID:12,activationGeneration:3,inputCounters:counters)
        check(context==WeChatPasteContext(pid:101,windowID:12,activationGeneration:3,inputCounters:counters),"Same window and interaction state can use the opaque fallback")
        check(context != WeChatPasteContext(pid:102,windowID:12,activationGeneration:3,inputCounters:counters),"Restarted WeChat cannot inherit the original window")
        check(context != WeChatPasteContext(pid:101,windowID:13,activationGeneration:3,inputCounters:counters),"Switching windows blocks opaque fallback")
        check(context != WeChatPasteContext(pid:101,windowID:12,activationGeneration:4,inputCounters:counters),"Switching away and back still blocks opaque fallback")
        for index in counters.indices {
            var changed=counters;changed[index]+=1
            check(context != WeChatPasteContext(pid:101,windowID:12,activationGeneration:3,inputCounters:changed),"Keyboard and mouse activity block opaque fallback")
        }
        check(DeliveryEvidence.alreadyAtCursor(value:"草稿这是一段内容",range:CFRange(location:8,length:0),inserted:"这是一段内容"),"Manual paste before focus polling cannot duplicate the result")
        check(!DeliveryEvidence.alreadyAtCursor(value:"这是一段内容",range:CFRange(location:0,length:0),inserted:"这是一段内容"),"Text elsewhere is not mistaken for a manual paste")
        check(!DeliveryEvidence.alreadyAtCursor(value:nil,range:nil,inserted:"测试"),"Unreadable cursor cannot fabricate existing content")
        check(DeliveryEvidence.alreadyAtCursor(value:"🙂C theft",range:CFRange(location:9,length:0),inserted:"C theft"),"English and emoji use native UTF16 cursor offsets")
        check(!DeliveryEvidence.alreadyAtCursor(value:"旧内容",range:CFRange(location:3,length:0),inserted:"新内容"),"Different existing draft still accepts late insertion")
        var late=PendingDeliveryLease(id:id,deadline:112,clipboardVersion:5)
        check(!late.claim(id:id,now:100,clipboardVersion:5,inputAvailable:false),"Wait without cursor does not consume result")
        check(!late.consumed,"Missing focus remains eligible")
        check(late.claim(id:id,now:102,clipboardVersion:5,inputAvailable:true),"Cursor activated after completion claims exactly one result")
        check(!late.claim(id:id,now:103,clipboardVersion:5,inputAvailable:true),"Persistent focus never inserts twice")
        var expired=PendingDeliveryLease(id:id,deadline:112,clipboardVersion:5)
        check(!expired.claim(id:id,now:112,clipboardVersion:5,inputAvailable:true),"Late cursor beyond deadline cannot receive stale result")
        var copied=PendingDeliveryLease(id:id,deadline:112,clipboardVersion:5)
        check(!copied.claim(id:id,now:101,clipboardVersion:6,inputAvailable:true),"User copied something new; abort automatic delivery")
        check(!copied.claim(id:id,now:102,clipboardVersion:5,inputAvailable:true),"Invalidated result cannot rearm")
        var replaced=PendingDeliveryLease(id:id,deadline:112,clipboardVersion:5)
        check(!replaced.claim(id:UUID(),now:101,clipboardVersion:5,inputAvailable:true),"New recording invalidates old result")
        for countDown in 0..<100{
            var delayed=PendingDeliveryLease(id:id,deadline:112,clipboardVersion:5)
            for tick in 0..<countDown{check(!delayed.claim(id:id,now:100+Double(tick)/10,clipboardVersion:5,inputAvailable:false),"Arbitrary unfocused interval cannot insert")}
            check(delayed.claim(id:id,now:100+Double(countDown)/10,clipboardVersion:5,inputAvailable:true),"Different timing binds the current cursor")
            check(!delayed.claim(id:id,now:111.9,clipboardVersion:5,inputAvailable:true),"Never duplicate after a successful claim")
        }
        print("Delivery evidence checks passed:",count)
    }
}
