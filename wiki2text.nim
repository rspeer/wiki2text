import streams, parsexml, re, strutils

# Wikitext handling
# -----------------

# This regex matches anywhere in the text that there *might* be wiki syntax
# that we have to clean up.
let ANYTHING_INTERESTING_RE: Regex = re"[*#:{[']"

# We skip the contents of these HTML tags entirely, and they don't nest
# inside each other.
let SKIP_SPANS = [
    "cite", "hiero", "gallery", "timeline", "noinclude",
    "caption", "ref", "references", "img", "source", "math"
]

# This regex is for matching and skipping over simple wikitext formatting.
let FORMATTING_RE: Regex = re(r"('''|''|^#\s*REDIRECT.*$|^[ *#:]+|^[|].*$)", {reMultiLine})
let BLANK_LINE_RE: Regex = re"\n\s*\n\s*\n"

let FAKE_FILENAME = "<wikipage>"
let TEMPLATE_SYMBOL = ""  # define this as a string to replace templates with

proc skipNestedChars(text: string, pos: var int, open: char, close: char) =
    ## Move our position 'pos' forward in the text, to skip a number of
    ## matching instances of the characters 'open' and 'close'.
    ##
    ## Precondition: text[pos] == open
    ## Postcondition: pos will increase by at least 1
    pos += 1
    var count = 1
    while count > 0 and pos < text.len:
        let nextPos: int = text.find({open, close}, pos)
        if nextPos == -1:
            # We can't find any more closing characters in the text.
            # Abort here so that there's something left.
            return
        else:
            let nextChar: char = text[nextPos]
            if nextChar == open:
                count += 1
            else:
                count -= 1
            pos = nextPos + 1

# forward declaration
proc filterWikitext(text: string): string

proc extractInternalLink(linkText: string): string =
    # Links with colons might be special MediaWiki syntax. Just throw them
    # all away.
    if linkText.contains(':'):
        return ""
    let contents: string = filterWikitext(linkText[2 .. < -2])
    let lastPart: int = contents.rfind('|') + 1
    return contents[lastPart .. -1]


proc extractExternalLink(linkText: string): string =
    let spacePos = linkText.find(' ')
    if spacePos == -1:
        return ""
    else:
        return filterWikitext(linkText[spacePos + 1 .. < -1])


proc filterLink(text: string, pos: var int): string =
    let startPos: int = pos

    # No matter what, move pos to the end of the link
    skipNestedChars(text, pos, '[', ']')

    # Figure out what we skipped. If it's an ugly pseudo-link, return
    # nothing.
    if text[startPos .. startPos + 1] == "[[":
        # Get the displayed text out of the internal link.
        return extractInternalLink(text[startPos .. <pos])
    else:
        # Get the displayed text out of the external link.
        return extractExternalLink(text[startPos .. <pos])


proc filterHTML(text: string): string =
    var xml: XmlParser
    let tstream: StringStream = newStringStream(text)
    result = ""
    xml.open(tstream, FAKE_FILENAME, options={reportWhitespace})
    while true:
        xml.next()
        case xml.kind
        of xmlElementStart, xmlElementOpen:
            if SKIP_SPANS.contains(xml.elementName):
                let skipTo: string = xml.elementName
                while true:
                    xml.next()
                    if xml.kind == xmlElementEnd and xml.elementName == skipTo:
                        break
                    elif xml.kind == xmlEof:
                        break
        of xmlCharData, xmlWhitespace:
            result.add(xml.charData)
        of xmlEof:
            break
        else:
            discard

    # return result implicitly
    xml.close


proc filterWikitext(text: string): string =
    ## Given the complete wikitext of an article, filter it for the part
    ## that's meant to be read as plain text.

    # This method works by building a 'result' string incrementally, and
    # advancing an index called 'pos' through the text as it goes. Some
    # of the procedures this relies on will also advance 'pos' themselves.
    result = ""
    var pos = 0
    while pos < text.len:
        # Skip to the next character that could be wiki syntax.
        var found: int = text.find(ANYTHING_INTERESTING_RE, pos)
        if found == -1:
            found = text.len

        # Add everything up until then to the string.
        if found > pos:
            result.add(text[pos .. <found])

        # Figure out what's here and deal with it.
        pos = found
        if pos < text.len:
            if text[pos .. pos+1] == "{{" or text[pos .. pos+1] == "{|":
                # replace template invocations with <T>
                skipNestedChars(text, pos, '{', '}')
                result.add(TEMPLATE_SYMBOL)

            elif text[pos] == '[':
                # pos gets updated by filterLink
                result.add(filterLink(text, pos))

            else:
                # Skip over formatting
                let matched = text.matchLen(FORMATTING_RE, pos)
                if matched > 0:
                    pos += matched
                else:
                    # We didn't match any of the cases, so output one character
                    # and proceed
                    result.add($(text[pos]))
                    pos += 1

# XML handling
# ------------

type
    TagType = enum
        TITLE, TEXT, REDIRECT, NS
    ArticleData = array[TagType, string]

var RELEVANT_XML_TAGS = ["title", "text", "redirect", "ns"]

proc handleArticle(article: ArticleData) =
    if article[NS] == "0" and article[REDIRECT] == "":
        echo("= $1 =" % [article[TITLE]])
        let text = filterWikitext(filterHTML(article[TEXT]))
        echo(text.replace(BLANK_LINE_RE, "\n"))


proc readMediaWikiXML(input: Stream, filename="<input>") =
    var xml: XmlParser
    var textBuffer: string = ""
    var article: ArticleData
    for tag in TITLE..NS:
        article[tag] = ""
    var gettingText: bool = false
    xml.open(input, filename, options={reportWhitespace})
    while true:
        xml.next()
        case xml.kind
        of xmlElementStart, xmlElementOpen:
            if RELEVANT_XML_TAGS.contains(xml.elementName):
                textBuffer.delete(0, textBuffer.len - 1)
                gettingText = true
            elif xml.elementName == "page":
                # clear redirect status
                article[REDIRECT] = ""
        of xmlElementEnd:
            case xml.elementName
            of "title":
                article[TITLE] = textBuffer
            of "text":
                article[TEXT] = textBuffer
            of "redirect":
                article[REDIRECT] = textBuffer
            of "ns":
                article[NS] = textBuffer
            of "page":
                handleArticle(article)
            else:
                discard
            gettingText = false
        of xmlCharData, xmlWhitespace:
            if gettingText:
                textBuffer.add(xml.charData)
        of xmlEof:
            break
        else:
            discard
    xml.close


when isMainModule:
    readMediaWikiXML(newFileStream(stdin))

