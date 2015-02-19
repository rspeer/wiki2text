import streams, parsexml, re, strutils

# Wikitext handling
# -----------------

# This regex matches anywhere in the text that there *might* be wiki syntax
# that we have to clean up.
var ANYTHING_INTERESTING_RE: Regex = re"[*#:{['=]"

# We skip the contents of these HTML tags entirely, and they don't nest
# inside each other.
var SKIP_SPANS = [
    "cite", "hiero", "gallery", "timeline", "noinclude",
    "caption", "ref", "references", "img", "source", "math"
]

# This regex is for matching and skipping over simple wikitext formatting.
var FORMATTING_RE: Regex = re(r"('''|''|^[ *#:]+|^[ =]+|[ =]+$)", {reMultiLine})

var FAKE_FILENAME = "<wikipage>"


proc skipNestedChars(text: string, pos: var int, open: char, close: char) =
    ## Move our position 'pos' forward in the text, to skip a number of
    ## matching instances of the characters 'open' and 'close'.
    ##
    ## Precondition: text[pos] == open
    ## Postcondition: pos will increase by at least 1
    pos += 1
    var count = 1
    while count > 0 and pos < text.len:
        var nextPos: int = text.find({open, close}, pos)
        if nextPos == -1:
            # We can't find any more closing characters in the text.
            # Abort here so that there's something left.
            return
        else:
            var nextChar: char = text[nextPos]
            if nextChar == open:
                count += 1
            else:
                count -= 1
            pos = nextPos + 1


# forward declaration
proc filterWikitext(text: string): string

proc extractInternalLink(linkText: string): string =
    var contents: string = filterWikitext(linkText[2 .. < -2])
    var parts: seq[string]
    parts = contents.split('|')
    if parts.len == 0:
        return ""

    var linkName: string = parts[parts.len - 1]
    if parts[0].contains(':') or linkName == "*":
        return ""
    return linkName


proc extractExternalLink(linkText: string): string =
    var spacePos = linkText.find(' ')
    if spacePos == -1:
        return ""
    else:
        return linkText[spacePos + 1 .. < -1]


proc filterLink(text: string, pos: var int): string =
    var startPos: int = pos

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
    var tstream: StringStream = newStringStream(text)
    result = ""
    xml.open(tstream, FAKE_FILENAME, options={reportWhitespace})
    while true:
        xml.next()
        case xml.kind
        of xmlElementStart, xmlElementOpen:
            if SKIP_SPANS.contains(xml.elementName):
                var skipTo: string = xml.elementName
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
    var matched: int
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
                # skip template invocations
                skipNestedChars(text, pos, '{', '}')

            elif text[pos] == '[':
                # pos gets updated by filterLink
                result.add(filterLink(text, pos))

            else:
                # Skip over formatting
                matched = text.matchLen(FORMATTING_RE, pos)
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
        echo("\n## ", article[TITLE])
        echo(filterWikitext(filterHTML(article[TEXT])))


proc readMediaWikiXML(input: Stream, filename="<input>") =
    var xml: XmlParser
    var textBuffer: string
    var article: ArticleData
    var gettingText: bool = false
    xml.open(input, filename, options={reportWhitespace})
    while true:
        xml.next()
        case xml.kind
        of xmlElementStart, xmlElementOpen:
            if RELEVANT_XML_TAGS.contains(xml.elementName):
                textBuffer = ""
                gettingText = true
            elif xml.elementName == "page":
                # clear article data for the new page
                for tag in TITLE..NS:
                    article[tag] = ""
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

