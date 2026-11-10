# -*- coding: utf-8 -*-
"""Conservative source edits for explicit dictation repairs.

No reference answers, dictionaries of test values, or model output are used.
Each edit must be justified by a local speech-repair marker, or an obvious
function-word restart. Ordinary comparisons and change-history stay intact.
"""
from dataclasses import dataclass
import re

PROTECTED=re.compile(r'“[^”]*”|「[^」]*」|『[^』]*』|‘[^’]*’|"[^"\n]*"|(?<!\w)\'[^\'\n]*\'(?!\w)|`[^`]*`|https?://[^\s，。！？]+|/[A-Za-z0-9_./?=&%-]+')
DISCUSSION=re.compile(r'原样|逐字|这几个字|这个字|这个词|语气词|连接词|说两遍|重复这个|记录.{0,5}变更过程|保留.{0,5}历史|\b(?:verbatim|literally|quoted|spelling)\b|\b(?:word|term|letter|say)\s+(?:um|uh|erm)\b',re.I)
NUM=r'(?:[+−-]?\d+(?:[.,]\d+)*|[负正]?[零〇一二两三四五六七八九十百千万亿]+(?:点[零〇一二三四五六七八九]+)?)'
CLOCK=rf'(?:(?:上午|下午|晚上|早上|中午|凌晨)?{NUM}(?:点|时)(?:半|一刻|三刻|{NUM}分)?|\d{{1,2}}:\d{{2}})'
WEEK=r'(?:(?:下下|上上|下|上|本|这)?周[一二三四五六日天1-7]|星期[一二三四五六日天1-7]|礼拜[一二三四五六日天1-7])(?:上午|下午|晚上|早上|中午|凌晨)?'
REL=r'(?:大后天|后天|明天|今天)(?:上午|下午|晚上|早上|中午|凌晨)?'
CALENDAR=rf'(?:(?:{NUM})年)?{NUM}月(?:{NUM}(?:日|号))?'
VALUE=re.compile(
    rf'(?P<money>{NUM}(?:亿元|万元|美元|欧元|人民币|元|块钱|块))'
    rf'|(?P<date>{CALENDAR}|{WEEK}(?:{CLOCK})?|{REL}(?:{CLOCK})?|{CLOCK})'
    rf'|(?P<quantity>{NUM}(?:个人|个月|小时|分钟|台|份|位|个|项|次|张|本|件|条|天|年|秒))'
    r'|(?P<weekday>\b(?:Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)\b)'
    r'|(?P<wordnumber>\b(?:zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\b)'
    rf'|(?P<number>{NUM})'
    r'|(?P<latin>[A-Za-z][A-Za-z0-9_+.-]*)',re.I)
MARKER=re.compile(r'(?<!对)不对(?!的|吗|吧|呢|[？?]|[啊呀哦](?:$|[。？！?!]))(?:[啊呀哦](?=[，,\s]))?|(?:刚才)?(?:说错了|讲错了)|(?<=[，,；;\n])\s*更正为|\bno\s*,?\s*actually\b|\bsorry\s*,?\s*I\s+mean\b|(?<=[，,])\s*(?:啊|哦)?不\s*[，,]',re.I)
CONNECTOR=re.compile(r'^[，,、：:\s]*(?:(?:最终|应该|应当)?(?:改成|改为|改到|换成|更正为|是|定为)|(?:刚才)?(?:说错了|讲错了)|不对)[，,、：:\s]*')
PREFIX_CUE=re.compile(r'(?:我要说的是|说的是|刚才说|我说的|我要输入|联系人是|收件人是|地点是|地点定在|联系|发给)(?P<value>[\u3400-\u9fff]{1,10})$')
COUNTER=re.compile(rf'{NUM}(?:个人|份|个|项|次|天|月|位|台|步)')
STARTERS=('我想','我觉得','我需要','请你','我们先','有','要','需要','用','看','发给','确认','先')
EMPHASIS={'非常','真的','好的','可以','谢谢','嗯','very','really'}

@dataclass
class Span:
    start:int
    end:int
    text:str
    kind:str

def protected(text):return [m.span()for m in PROTECTED.finditer(text)]
def overlaps(a,b,spans):return any(x<b and a<y for x,y in spans)

def values(text):
    hidden=protected(text);result=[]
    lexical=[m.span()for m in re.finditer(r'一下|一定|一直|一起|一样|一旦|一般|一共|万一|一方面',text)]
    masked=list(text)
    for a,b in lexical:masked[a:b]=' '*(b-a)
    for m in VALUE.finditer(''.join(masked)):
        if overlaps(m.start(),m.end(),hidden+lexical):continue
        result.append(Span(m.start(),m.end(),m.group(0),m.lastgroup))
    return result

def compatible(a,b):
    if a.kind==b.kind:return True
    if a.kind in {'date','weekday'}and b.kind in {'date','weekday'}:return True
    if a.kind in {'number','wordnumber'}and b.kind in {'number','wordnumber','money','quantity'}:return True
    return False

def trim_separators(s):return s.strip('，,、：: \t\r\n')

def next_start(text,index):
    # Consume only metalinguistic repair markers, never ordinary clause content.
    start=index
    for _ in range(6):
        # 是不是/是否 ask a question, rather than announcing a replacement.
        if re.match(r'[，,、：:\s]*(?:是不是|是否|能不能|有没有|可不可以)',text[start:]):break
        m=CONNECTOR.match(text[start:])
        if not m:break
        start+=m.end()
    while start<len(text)and text[start]in '，,、：: \t\r\n':start+=1
    return start

def nearest_before(text,index,all_values):
    candidates=[v for v in all_values if v.end<=index and index-v.end<=10]
    for value in reversed(candidates):
        gap=text[value.end:index]
        if re.search(r'[！？!?；;\n]',gap):continue
        if not re.fullmatch(r'[，,。.、：:\s]*(?:开会|召开会议|发货|交付|上线|出发|发布|联系|确认|版本|就有)?[，,。.、：:\s]*',gap):continue
        return value
    # Bare Chinese names/choices need a strong field or speech-reference cue.
    endpoint=len(text[:index].rstrip('，,。.、：: \t\r\n'))
    clause_start=max([text.rfind(ch,0,endpoint)for ch in '。！？!?；;\n']+[-1])+1
    clause=text[clause_start:endpoint].rstrip('，,、：: \t')
    cue=PREFIX_CUE.search(clause)
    if cue:
        value=cue.group('value')
        if not re.search(r'然后|但是|并且|以及|和|或者|再|不要',value):
            return Span(clause_start+cue.start('value'),clause_start+cue.end('value'),value,'entity')
    return None

def next_value(text,index,kind,all_values):
    start=next_start(text,index)
    for value in all_values:
        if value.start==start:
            if kind in {'latin','entity'}and value.kind=='latin':
                # A multi-word predicate is not a single entity correction.
                tail=text[value.end:]
                if re.match(r'\s+[A-Za-z]',tail):return None
            return value
        if value.start>start:break
    if kind=='entity':
        m=re.match(r'[\u3400-\u9fff]{1,10}(?=[，,。！？!?；;\n]|$)',text[start:])
        if m and not re.search(r'然后|但是|并且|以及|或者|发货|交付|开会',m.group(0)):
            # A request to verify the old name is not a new name. Keep the
            # unresolved statement instead of replacing its object with prose.
            if re.match(r'[啊呀哦]?(?:请|帮我|帮忙|能不能|可不可以|是否|是不是|有没有|怎么|为什么|哪[个位里儿]|麻烦)',m.group(0))or re.search(r'[吗呢吧]$',m.group(0)):return None
            return Span(start,start+m.end(),m.group(0),'entity')
    return None

def retract_one(text):
    spans=protected(text);all_values=values(text)
    for marker in MARKER.finditer(text):
        if overlaps(marker.start(),marker.end(),spans):continue
        if re.search(r'(?:不是|没有|没|并非)$',text[max(0,marker.start()-3):marker.start()]):continue
        old=nearest_before(text,marker.start(),all_values)
        if old is None:continue
        if '更正为'in marker.group(0)and re.search(r'请|把|将|从',text[max(0,old.start-20):old.start]):continue
        new=next_value(text,marker.end(),old.kind,all_values)
        if new is None or not compatible(old,new):continue
        if overlaps(old.start,new.end,spans):continue
        # A partial time replacement is ambiguous unless the speaker explicitly
        # announces a final whole value. Never guess that an omitted time survives.
        if old.kind=='date'and re.search(WEEK,old.text)and re.search(CLOCK,old.text)and not re.search(CLOCK,new.text)and'最终'not in text[marker.start():new.start]:continue
        gap=trim_separators(text[old.end:marker.start()]).strip('。. ')
        modality='应该是'if '应该'in text[marker.start():new.start]else'应当是'if'应当'in text[marker.start():new.start]else''
        # Preserve a repeated predicate exactly once, without inventing a new one.
        tail=text[new.end:]
        if gap and tail.startswith(gap):gap=''
        elif gap and re.sub(r'^(?:不|没|未|不要|不能)','',tail).startswith(gap):gap=''
        elif gap and tail and tail[0]not in '，,。.!！?？；;\n ':continue
        prefix=text[:old.start]
        if modality:
            # A repeated copula or preposition is not part of the corrected date.
            # Keep the speaker's uncertainty while placing it grammatically.
            if prefix.endswith('不是'):continue
            if prefix.endswith('是'):prefix=re.sub(r'(?:应该|应当)?是$','',prefix)
            else:
                preposition=re.search(r'(从|截至|截止到|到|在)$',prefix)
                if preposition:
                    prefix=prefix[:preposition.start()]+modality[:-1]+preposition.group(0);modality=''
        result=prefix+modality+new.text+gap+tail
        return result,True
    # Explicit withdrawal of what the speaker just said; generic commands such
    # as "make the old contract void" are intentionally not collapsed.
    pat=re.compile(r'(?:刚才的|刚才说的|前面说的)(?P<old>[^，,。！？!?；;\n]{1,18})作废[，,\s]*(?:最终)?以(?P<new>[^，,。！？!?；;\n]{1,18})为准')
    for m in pat.finditer(text):
        if overlaps(m.start(),m.end(),spans):continue
        old=values(m.group('old'));new=values(m.group('new'))
        if len(old)==len(new)==1 and old[0].text==m.group('old')and new[0].text==m.group('new')and compatible(old[0],new[0]):
            return text[:m.start()]+m.group('new')+text[m.end():],True
    return text,False

FIELDS={
    'meeting':('会议时间','开会时间','会议安排'),
    'budget':('预算','预算金额'),
    'delivery':('交付时间','交付日期'),
    'contact':('联系人','收件人'),
    'place':('地点','会议地点'),
}

def retract_remote(text):
    """Resolve a named-field retraction across intervening independent facts.

    Requires explicit reference to what was just said, one unambiguous prior
    assignment, and a compatible replacement. Narrative changes are not repairs.
    """
    hidden=protected(text);all_values=values(text)
    names='|'.join(re.escape(s)for group in FIELDS.values()for s in sorted(group,key=len,reverse=True))
    pattern=re.compile(r'(?:刚才|前面)(?:的)?(?P<field>'+names+r')(?:说错了|写错了)[，,\s]*(?:最终)?(?:改成|改为|更正为|是)[，,\s]*')
    for m in pattern.finditer(text):
        if overlaps(m.start(),m.end(),hidden):continue
        aliases=next(group for group in FIELDS.values()if m.group('field')in group)
        eligible=[]
        for v in all_values:
            if v.end>=m.start():break
            start=max([text.rfind(ch,0,v.start)for ch in '，,。！？!?；;\n']+[-1])+1
            prefix=text[start:v.start]
            if any(name in prefix for name in aliases)and len(prefix)<26:eligible.append(v)
        if len(eligible)!=1:continue
        old=eligible[0];new=next_value(text,m.end(),old.kind,all_values)
        if new is None or not compatible(old,new)or overlaps(new.start,new.end,hidden):continue
        middle=text[old.end:m.start()];tail=text[new.end:]
        if middle.endswith('。')and tail.startswith('。'):tail=tail[1:]
        return text[:old.start]+new.text+middle+tail,True
    return text,False

def polarity_form(text):
    """Compare the same claim with explicit opposite polarity, never two actors."""
    value=text.strip()
    value=re.sub(r"\bdon['’]t\b",'do not',value,flags=re.I)
    value=re.sub(r"\bcan['’]t\b",'can not',value,flags=re.I)
    value=re.sub(r'\b(?:do\s+not|not)\b','',value,flags=re.I)
    value=re.sub(r'已经|尚未|还没有|还没|没有','',value)
    for pattern,replacement in [('不可以|不能|可以','可以'),('有',''),('不是|是','是'),('不要|要','要')]:
        value=re.sub(pattern,replacement,value)
    value=re.sub(r'不|没|未','',value)
    return ''.join(c for c in value.casefold()if c.isalnum())

def retract_polarity(text):
    # Only same-claim polarity reversals with an explicit speech repair. A
    # disagreement between two people, a condition or a quotation never matches.
    hidden=protected(text)
    pattern=re.compile(r'(?P<old>[^，,。！？!?；;\n]{3,72})[，,。.]\s*(?:不对|说错了|no\s*,?\s*actually|sorry\s*,?\s*I\s+mean)[，,\s]*(?:(?:我的意思是|我刚才想说的是|应该是|改成)[，,\s]*)?(?P<new>[^，,。！？!?；;\n]{3,72})',re.I)
    for match in pattern.finditer(text):
        old,new=match.group('old'),match.group('new')
        if overlaps(match.start(),match.end(),hidden):continue
        if any(x in old+new for x in ('如果','除非','假如','他说','她说','以前','原来','之前')):continue
        if not re.search(r'不|没|未|\bnot\b|n[’\']t',old+new,re.I):continue
        if polarity_form(old)!=polarity_form(new):continue
        return text[:match.start()]+new+text[match.end():],True
    return text,False

def retract_named_slots(text):
    """Apply explicitly named replacement slots, never the last arbitrary value.

    Independent clauses between the assignment and its correction survive. A
    field with two eligible values is ambiguous and deliberately left alone.
    """
    hidden=protected(text)
    cue=re.search(r'[，,。.]\s*(?:不对[，,\s]*(?:我说的是[，,\s]*)?|刚才说错了[，,\s]*)',text)
    if not cue or overlaps(cue.start(),len(text),hidden):return text,False
    prefix=text[:cue.start()];tail=text[cue.end():]
    if re.search(r'如果|除非|假如|他说|她说|以前|原来|之前',prefix):return text,False
    specs={'时间':{'date','weekday'},'日期':{'date','weekday'},'数量':{'quantity'},'预算':{'money','number','wordnumber'}}
    pattern=re.compile(r'(?P<field>时间|日期|数量|预算)(?:改成|改为|更正为)[，,\s]*')
    replacements=[];consumed=0
    for m in pattern.finditer(tail):
        if tail[consumed:m.start()].strip('，,、 \t'):return text,False
        options=[v for v in values(prefix)if v.kind in specs[m.group('field')]]
        if m.group('field')=='预算':
            options=[v for v in options if re.search(r'预算(?:金额)?(?:是|为)?\s*$',prefix[:v.start])]
        if len(options)!=1:return text,False
        old=options[0];new=next_value(tail,m.end(),old.kind,values(tail))
        if new is None or not compatible(old,new):return text,False
        if any(old.start==o.start for o,n in replacements):return text,False
        replacements.append((old,new));consumed=new.end
    if not replacements:return text,False
    # Replacement clauses must be a contiguous prefix of the speech repair.
    # Leave any following statement, including unchanged fields, intact.
    for old,new in sorted(replacements,key=lambda pair:pair[0].start,reverse=True):
        prefix=prefix[:old.start]+new.text+prefix[old.end:]
    remainder=tail[consumed:]
    if remainder and remainder[0]not in '，,。.!！?？；;\n ':return text,False
    if remainder.startswith(('。','.')):return prefix+remainder,True
    return prefix+remainder,True

def retract_city(text):
    # A speaker explicitly naming the mistaken field is stronger than a bare
    # "is X". Require one literal location assignment, without conditions.
    m=re.search(r'[，,。.]\s*不对[，,\s]*我说错(?:城市|地点)了[，,\s]*是(?P<new>[\u3400-\u9fff]{1,10})(?=[，,。！？!?；;]|$)',text)
    if not m or overlaps(0,m.end(),protected(text)):return text,False
    prefix=text[:m.start()]
    if re.search(r'如果|除非|假如|他说|她说|以前|原来|之前',prefix):return text,False
    places=list(re.finditer(r'(?:地点(?:是|在)|(?:会议|活动|聚会|地点)(?:是)?在)(?P<old>[\u3400-\u9fff]{1,10})(?=[，,。！？!?；;]|$)',prefix))
    if len(places)!=1:return text,False
    old=places[0]
    return prefix[:old.start('old')]+m.group('new')+prefix[old.end('old'):]+text[m.end():],True

def retract_statement(text):
    """Bounded explicit restatements with matching subject/event anchors.

    These are source edits, not semantic guesses from a language model. A new
    clause may replace a withdrawn claim only under one of the explicit frames
    below; quoted, conditional, historical and multi-actor claims are excluded.
    """
    english=re.match(r'(?P<old>I (?:said|meant) [^.\n]{3,160})[.,]\s*(?:Sorry[,.]?\s*(?:I meant\s+)?|sorry[,.]?\s*)(?P<new>[^\n]+)$',text)
    if english and not overlaps(0,len(text),protected(text)):
        new=english.group('new')
        explicit=bool(re.search(r'\bsorry[,.]?\s+I meant\b',text,re.I))
        stop={'said','meant','should','would','could','have','that','this','only','after','until','sorry','immediately'}
        anchors=lambda s:{w.lower()for w in re.findall(r'[A-Za-z]{4,}',s)if w.lower()not in stop}
        same_event=bool(anchors(english.group('old'))&anchors(new))
        if (explicit or same_event)and not re.search(r'\b(?:yesterday|previously|used to|if|unless|he said|she said)\b',text,re.I):
            return new[:1].upper()+new[1:],True
    marker=re.search(r'[，,。.]\s*(?P<cue>或者不对|不对|等等[，,\s]*我想改成)[，,\s]*',text)
    if not marker:return text,False
    prefix=text[:marker.start()];tail=text[marker.end():]
    if overlaps(0,len(text),protected(text)):return text,False
    if re.search(r'如果|除非|假如|他说|她说|以前|原来|之前',prefix):return text,False
    # Never discard an independent earlier clause while retracting a later one.
    split=max([prefix.rfind(ch)for ch in '，,。！？!?；;\n']+[-1])+1
    earlier,old=prefix[:split],prefix[split:]
    first=re.split(r'[，,。！？!?；;\n]',tail,maxsplit=1)[0]
    if not first:return text,False
    if re.search(r'(?:他说|她说|他们|你们)',first):return text,False
    # Same predicate, omitted topic: preserve the exact stance and subject.
    restated=re.match(r'(?:我的意思是|我刚才想说的是)(?P<new>(?:还)?(?:不能|不可以|不要|没有|还没有)[\u3400-\u9fff]{1,18})$',first)
    if restated:
        oldclaim=re.fullmatch(r'(?P<topic>[^，,。！？!?；;]{1,30}?)(?:已经|还)?(?:可以|能够|能|要)(?P<verb>[\u3400-\u9fff]{1,12})',old)
        # A negator must never be mistaken for part of the inherited topic.
        # A second person's opinion is also not the speaker's own assertion.
        clean_topic=oldclaim and not re.search(r'(?:不|没|未|无)$',oldclaim.group('topic'))and not re.match(r'你|他|她',oldclaim.group('topic'))
        if clean_topic and restated.group('new').endswith(oldclaim.group('verb')):
            return earlier+oldclaim.group('topic')+restated.group('new')+tail[len(first):],True
    # Explicitly retracting the just-spoken time, repeating the same event.
    time_echo=re.match(r'不是(?P<old>今天|明天|后天|'+WEEK+r')[，,\s]*是(?P<new>[^，,。！？!?；;]+)',tail)
    if time_echo and old.startswith(time_echo.group('old')):
        action=re.sub(r'^(?:先|再|就)+','',old[len(time_echo.group('old')):]).rstrip('了')
        if len(action)>=2 and time_echo.group('new').endswith(action):
            return earlier+tail[time_echo.start('new'):],True
    # Narrow the scope of a completion claim explicitly withdrawn with 不对.
    if re.search(r'(?:已经|全部|完全).{0,10}(?:修好|完成|解决)了?$',old)and first.startswith('只'):
        verb=re.search(r'修|完成|解决',old)
        if verb and verb.group(0)in first:return earlier+tail,True
    # The same "first use" action is restarted with a different choice.
    if marker.group('cue')=='或者不对'and old.startswith('先用')and first.startswith('先用'):
        return earlier+tail,True
    # Preserve versus delete is an explicitly opposed action on the same item.
    if re.fullmatch(r'(?:这个|该)(?:文件|文档|记录|原件)(?:可以|能够|能)删除',old)and re.match(r'(?:应该|应当|必须)保留(?:原件|原文)',first):
        return earlier+tail,True
    # Recipient elision: carry only one explicitly spoken 给<recipient> when
    # the replacement repeats the same send verb and supplies no new recipient.
    if marker.group('cue').startswith('等等'):
        send=re.fullmatch(r'先给(?P<to>[\u3400-\u9fff]{1,8})发(?P<item>[^，,。！？!?；;]+)',old)
        if send and first.startswith('先发')and '给'not in first:
            return earlier+'先给'+send.group('to')+'发'+tail[2:],True
    return text,False

def remove_restarts(text):
    removed=0
    for _ in range(16):
        spans=protected(text);changed=False
        for start in range(len(text)):
            if overlaps(start,start+1,spans):continue
            for width in range(2,min(17,len(text)-start+1)):
                unit=text[start:start+width]
                if not unit or unit in EMPHASIS or COUNTER.fullmatch(unit):continue
                if not any(unit.startswith(root)for root in STARTERS):continue
                if not re.fullmatch(r'[\u3400-\u9fffA-Za-z0-9]+',unit):continue
                count=1;end=start+width
                while True:
                    sep=re.match(r'[，,、\s]*',text[end:]).end()
                    next_pos=end+sep
                    if not text.startswith(unit,next_pos):break
                    count+=1;end=next_pos+width
                if count<2 or overlaps(start,end,spans):continue
                text=text[:start]+unit+text[end:];removed+=count-1;changed=True;break
            if changed:break
        if not changed:break
    # English pronoun restarts, not grammatical "that that" or emphatic "no no".
    spans=protected(text)
    pat=re.compile(r'\b(I|we|you)\b(?:[ ,]+\1\b)+(?=\s+(?:want|need|think|feel|can|will|should|am|are)\b)',re.I)
    edits=[m for m in pat.finditer(text)if not overlaps(m.start(),m.end(),spans)]
    for m in reversed(edits):text=text[:m.start()]+m.group(1)+text[m.end():];removed+=1
    return text,removed

def remove_fillers(text):
    if not text.strip()or re.fullmatch(r'[呃额嗯啊，,。.!！?？\s]+',text):return text,0
    if re.fullmatch(r'(?:um|uh|erm)[,.!?;\s]*',text,re.I):return text,0
    spans=protected(text);edits=[]
    # Filled pauses, bounded as words. "um" inside a name or literal is untouched.
    pat=re.compile(r'(?<![A-Za-z])(?:um|uh|erm)(?:[，,\s]+|$)|(?<![\u3400-\u9fffA-Za-z])[呃额][，,、\s]+|^[呃额](?=然后|就是|这个|那个|我们|我|请)',re.I)
    for m in pat.finditer(text):
        if not overlaps(m.start(),m.end(),spans):edits.append(m)
    for m in reversed(edits):text=text[:m.start()]+text[m.end():]
    count=len(edits)
    # A comma-bounded hesitation inside prose is different from affirmative 嗯/嗯嗯.
    # Keep quoted/reported replies and explicit discussion of the syllable intact.
    spans=protected(text);hesitations=[]
    pause=re.compile(r'(?P<boundary>^|[，,。！？!?；;\n])(?P<syllable>嗯)[，,\s]+')
    acknowledgement=re.compile(r'^(?:嗯|哼|好|对|是的|没错|当然|行(?:$|[，,。！!\s])|可以|知道|明白|收到|同意|不行|不用)')
    for m in pause.finditer(text):
        if overlaps(m.start(),m.end(),spans):continue
        after=text[m.end():];before=text[:m.start()]
        if not after.strip()or acknowledgement.match(after)or re.match(r'^(?:我|我们)?(?:同意|不同意|赞成|反对|确认|知道|明白)',after):continue
        if re.search(r'(?:回答|回应|答应|点头|说了|说了一声|发出|他说|她说|我说|他问|她问|问道|答道|说道)[，,\s]*$',before):continue
        if not re.search(r'[\u3400-\u9fffA-Za-z]',after):continue
        hesitations.append(m)
    for m in reversed(hesitations):text=text[:m.start()]+m.group('boundary')+text[m.end():]
    return text,count+len(hesitations)

def remove_syllable_restarts(text):
    """Fold partial starts of common function words; keep emphasis and literals."""
    count=0
    for word in ('这里','这个','这样','那里','那个','那么','然后','就'):
        # Do not cross a comma: 去那，那么... contains two meaningful 那.
        # A repeated 就 inside 将就就好/成就就来自... is also grammatical.
        boundary=r'(?:(?<![\u3400-\u9fff])|(?<=[我你他她它]))'if word=='就'else''
        pattern=re.compile(boundary+r'(?:'+re.escape(word[0])+r')+'+re.escape(word))
        spans=protected(text)
        edits=[m for m in pattern.finditer(text)if not overlaps(m.start(),m.end(),spans)]
        for m in reversed(edits):
            text=text[:m.start()]+word+text[m.end():];count+=1
    # Repeated superlative modifiers in ordinary dictation, as in 最最最快.
    # Restrict the following predicate; standalone 最 and literal discussion
    # are not speech repairs. Quotes/code/URLs and explicit emphasis survive.
    if not re.search(r'(?:几个|多个|重复|连着|连续).{0,8}最|最.{0,8}(?:重复|几个字|几个最)|(?:强调|重读).{0,12}最',text):
        pattern=re.compile(r'最{2,}(?=快|慢|好|差|高|低|大|小|多|少|早|晚|新|旧|强|弱|优|佳|准|近|远|重要|清楚|清晰|安全|稳定|简单|方便|容易|便宜|贵|合适|成熟|先进|流畅|准确)')
        spans=protected(text)
        edits=[m for m in pattern.finditer(text)if not overlaps(m.start(),m.end(),spans)]
        for m in reversed(edits):
            text=text[:m.start()]+'最'+text[m.end():];count+=len(m.group(0))-1
    return text,count

REPORTING_TAIL = re.compile(r'(?:他说|她说|我说|他问|她问|问道|答道|说道|原话|回答|回应|台词|引文)[^。！？!?]{0,24}[。！？!?]?$')
WITHDRAWN_TAIL = re.compile(
    r'[，,。！？!?；;\n]\s*(?P<tail>'
    r'(?:(?:嗯|呃|额|然后呢?|还有|另外|那个?|最后)[，,、。；;\s]*)*'
    r'我(?:建议|想建议|想说|想问|想告诉|想补充|想提醒|打算|准备|觉得|希望)(?:你们?|大家)?'
    r'[，,。；;…—\n]+\s*'
    r'(?:(?:嗯|呃|额)[，,、\s]*)*(?:没什么(?:了)?|算了|不说了|不提了)'
    r'[。！!…\s]*)$'
)

def withdrawn_tail_prefix(text):
    """Bound the source span the editor may decide to omit; never edit here."""
    match=WITHDRAWN_TAIL.search(text)
    if not match or DISCUSSION.search(text):return None
    if overlaps(match.start('tail'),match.end(),protected(text)):return None
    prefix=text[:match.start('tail')].rstrip()
    if sum(c.isalnum()for c in prefix)<4 or REPORTING_TAIL.search(prefix):return None
    return prefix

def remove_thinking_tail(text):
    """Remove a bounded dictation aside after a complete substantive sentence.

    A thinking cue plus an explicit finish is required. A leading filled pause
    also permits a bare thinking aside. This never fixes an ASR word by guessing.
    The short stutter/particle ending is only eligible inside this complete aside,
    not as a general replacement of 没 or 的 elsewhere in the transcript.
    """
    sep=r'[，,、。.!！?？\s]*'
    pause=rf'(?:嗯|呃|额){sep}'
    thinking=rf'(?:(?:然后|再|我|让我){sep})*(?:想想|想一想|想一下){sep}'
    finish=rf'(?:(?:没{sep})+(?:了|有了|的)|没有了|没什么了|没有别的了|没有其他的了|就这些|就这样|暂时没有了){sep}'
    pattern=re.compile(rf'(?P<boundary>[。！？!?])\s*(?P<aside>(?:(?:{pause})+{thinking}(?:{pause})*(?:{finish})?|{thinking}(?:{pause})*{finish}))$')
    match=pattern.search(text)
    if not match:return text,0
    body=text[:match.start()]+match.group('boundary')
    if sum(c.isalnum()for c in body)<12:return text,0
    if overlaps(match.start('aside'),match.end(),protected(text)):return text,0
    if REPORTING_TAIL.search(body):return text,0
    return body.rstrip(),1

def remove_self_restarts(text):
    """Fold an unpunctuated self-stutter or an abandoned bare thinking start.

    The complete following predicate and its actor survive. Comma-separated
    emphatic pronouns, isolated letters/words and quoted speech stay untouched.
    """
    count=0
    pattern=re.compile(r'(?P<boundary>^|[，,。！？!?；;\n])我{2,}(?=现在|今天|明天|觉得|认为|想|需要|希望|准备|打算)')
    spans=protected(text)
    matches=[m for m in pattern.finditer(text)if not overlaps(m.start(),m.end(),spans)]
    for m in reversed(matches):
        count+=len(m.group(0))-len(m.group('boundary'))-1
        text=text[:m.start()]+m.group('boundary')+'我'+text[m.end():]
    # 想你/想去... have objects/complements and cannot match this bare start.
    pattern=re.compile(r'(?P<boundary>^|[，,。！？!?；;\n])我想[，,\s]+(?:(?:哎|呃|额|嗯|那个)[，,\s]+)*(?=我(?:在想|想|觉得|认为))')
    spans=protected(text);matches=[m for m in pattern.finditer(text)if not overlaps(m.start(),m.end(),spans)]
    for m in reversed(matches):text=text[:m.start()]+m.group('boundary')+text[m.end():];count+=1
    return text,count

def prepare_transcript(text):
    stats={'correction_steps':0,'restart_removals':0,'filler_removals':0,'fragment_folds':0,'thinking_tail_removals':0,'syllable_restart_removals':0}
    if DISCUSSION.search(text):
        # An explicitly separated initial pause before a request is outside
        # the literal being discussed. Do not scan inside that discussion.
        pause=re.match(r'^[呃额][，,\s]+(?=请|帮|我想问)',text)
        if pause:text=text[pause.end():];stats['filler_removals']=1
        return text,stats
    text,stats['thinking_tail_removals']=remove_thinking_tail(text)
    text,stats['filler_removals']=remove_fillers(text)
    text,stats['restart_removals']=remove_restarts(text)
    text,stats['syllable_restart_removals']=remove_syllable_restarts(text)
    for _ in range(32):
        text,changed=retract_named_slots(text)
        if not changed:text,changed=retract_city(text)
        if not changed:text,changed=retract_statement(text)
        if not changed:text,changed=retract_polarity(text)
        if not changed:text,changed=retract_one(text)
        if not changed:text,changed=retract_remote(text)
        if not changed:break
        stats['correction_steps']+=1
    # A copular false start can be the topic of the immediately following
    # question. Limit this to noun phrases, not "是你说的" or a quoted claim.
    spans=protected(text)
    pat=re.compile(r'(但是|可是|然而)[，,\s]*是(?P<topic>[\u3400-\u9fff]{0,8}(?:模型|服务|软件|应用|接口|文件|账号|方案|问题))[，,\s]+(?P<question>是不是|有没有|能不能|会不会)')
    edits=[m for m in pat.finditer(text)if not overlaps(m.start(),m.end(),spans)and not re.search(r'[我你他她它]',m.group('topic'))]
    for m in reversed(edits):
        text=text[:m.start()]+m.group(1)+'，'+m.group('topic')+m.group('question')+text[m.end():];stats['fragment_folds']+=1
    text,restarts=remove_self_restarts(text);stats['restart_removals']+=restarts
    return text.strip(),stats
