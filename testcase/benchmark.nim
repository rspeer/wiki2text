import streams, parsexml, times, strutils

proc benchmarkXML(input: Stream, filename="<input>") =
    var xml: XmlParser
    var count: int = 0
    var chars: int = 0
    var t0 = cpuTime()
    xml.open(input, filename, options={reportWhitespace})
    while true:
        xml.next()
        case xml.kind
        of xmlElementStart:
            chars += len(xml.elementName)
        of xmlElementEnd:
            count += 1
            chars += len(xml.elementName)
            let elapsed = cpuTime() - t0
            if count == 100_000:
                let rate = toFloat(count) / elapsed
                let charRate = toFloat(chars) / elapsed
                t0 = cpuTime()
                count = 0
                chars = 0
                echo("$1 elements/second, $2 chars/second" % [$(rate.toInt), $(charRate.toInt)])
        of xmlCharData:
            chars += len(xml.charData)
        of xmlComment:
            chars += len(xml.charData)
        of xmlEof:
            break
        else:
            discard
    xml.close


when isMainModule:
    benchmarkXML(newFileStream(stdin))

