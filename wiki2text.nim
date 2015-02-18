import streams, parsexml

type
    TagType = enum
        TITLE, TEXT, REDIRECT, NS
    ArticleData = array[TagType, string]

# These tags are the only tags we will extract text from, and they never
# nest inside each other.
var relevantTags: array[4, string] = ["title", "text", "redirect", "ns"]


proc handleArticle(article: ArticleData) =
    if article[NS] == "0" and article[REDIRECT] == "":
        echo("\n## ", article[TITLE])
        echo(article[TEXT])


proc readMediaWikiXML(input: Stream, filename="<input>") =
    var x: XmlParser
    var textBuffer: string = ""
    var article: ArticleData
    var active: bool = false
    x.open(input, filename)
    while true:
        x.next()
        case x.kind
        of xmlElementStart, xmlElementOpen:
            if relevantTags.contains(x.elementName):
                textBuffer = ""
                active = true
            elif x.elementName == "page":
                # clear article data for the new page
                for tag in TITLE..NS:
                    article[tag] = ""
        of xmlElementEnd:
            case x.elementName
            of "title":
                article[TITLE] = textBuffer
            of "text":
                article[TEXT] = textBuffer
            of "ns":
                article[NS] = textBuffer
            of "redirect":
                article[REDIRECT] = textBuffer
            of "page":
                handleArticle(article)
            else:
                discard
            active = false
            textBuffer = ""
        of xmlCharData:
            if active:
                textBuffer.add(x.charData)
        of xmlEof:
            break
        else:
            discard


when isMainModule:
    readMediaWikiXML(newFileStream(stdin))

