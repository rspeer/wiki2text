# There are two steps to interpreting a Wikipedia XML file. First, we need to
# get the data out of the XML, which requires a streaming XML parser.
#
# Then, we need to deal with the actual content of an article, which is in a
# hybrid of HTML and MediaWiki's own syntax. The way that we handle the HTML
# tags (mostly for the purpose of skipping their contents) is to run them
# through another streaming XML parser. This one doesn't really need to be
# streaming, but it might as well be so that we can reuse the same Nim library.

import streams, parsexml, re, strutils, unicode, parseopt2

# Wikitext handling
# -----------------

# This regex matches anywhere in the text that there *might* be wiki syntax
# that we have to clean up.
let ANYTHING_INTERESTING_RE: Regex = re"[*#:;|!{['_]"

# We skip the contents of these HTML tags entirely, and they don't nest
# inside each other.
const SKIP_SPANS = [
    "cite", "ref", "hiero", "gallery", "timeline", "noinclude",
    "caption", "references", "img", "source", "math"
]

# This regex is for matching and skipping over simple wikitext formatting.
# Here's the breakdown of the patterns we're matching:
#
#   '''?                         = Bold and italic formatting (two or three apostrophes)
#   ^#\s*(REDIRECT|redirect).*$  = Redirect syntax
#   ^[ *#:;]+                    = Bullets and indentation markers at the start of a line
#   ^__.*__$                     = table-of-contents directives
#   ^[|!].*$                     = Table detritus
#
# "Table detritus" might require some explanation. Tables, delimited by {|
# and |}, are something that we skip separately in filterWikitext. But
# because MediaWiki is insane like this, some tables are made using syntax
# that uses a template for the beginning of the table and |} syntax for the
# end.
#
# Because we don't know what's in templates, when this happens, we end up
# just seeing the inside and end of the table as if it were text. Usually,
# though, these lines begin with the cell separator |, so we can just filter
# those out.

let FORMATTING_RE: Regex = re(r"('''?|^#\s*redirect.*$|^[ *#:;]+|^[|!].*$|^__.*__$)", {reMultiLine, reIgnoreCase})

# This regex matches sequences of more than one blank line.
let BLANK_LINE_RE: Regex = re"\n\s*\n\s*\n"

let WORD_SEPARATOR_RE: Regex = re"'?([\x01-\x26\x28-\x2f\x3a-\x40\x5b-\x60\x7b-\x7f]|(\xc2[\x80-\xbf])|(\xe2\x80.)|(\xe2\x81[\x80-\xaf])|(\xe3\x80[\x80-\x9f]))'?"

let EMPTY_REF_RE: Regex = re(r"<ref [^>]+/\s*>", {reIgnoreCase})

const FAKE_FILENAME = "<wikipage>"

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
            # Jump to the end and abort.
            pos = text.len
            return
        else:
            let nextChar: char = text[nextPos]
            if nextChar == open:
                count += 1
            else:
                count -= 1
            pos = nextPos + 1


# Convert Unicode text to lowercase.
# I hope this eventually ends up in the standard library.
proc unicodeLower(text: string): string =
    result = ""
    for rune in runes(text):
        result.add(rune.toLower.toUTF8)


# forward declaration
proc filterWikitext(text: string): string

proc extractInternalLink(linkText: string): string =
    # Links with colons might be special MediaWiki syntax. Just throw them
    # all away.
    if linkText.contains(':'):
        return ""
    # If the brackets are unbalanced, return nothing.
    if linkText[^2] != ']' or linkText[^1] != ']':
        return ""
    let contents: string = filterWikitext(linkText[2 .. ^3])
    let lastPart: int = contents.rfind('|') + 1
    return contents[lastPart .. ^1]


proc extractExternalLink(linkText: string): string =
    let spacePos = linkText.find(' ')
    if spacePos == -1:
        return ""
    else:
        if linkText[^1] == ']':
            return ""
        else:
            return filterWikitext(linkText[spacePos + 1 .. ^2])


proc filterLink(text: string, pos: var int): string =
    let startPos: int = pos

    # No matter what, move pos to the end of the link
    skipNestedChars(text, pos, '[', ']')

    # Figure out what we skipped and try to return its displayed content.
    if text.continuesWith("[[", startPos):
        # Get the displayed text out of the internal link.
        return extractInternalLink(text[startPos .. <pos])
    else:
        # Get the displayed text out of the external link.
        return extractExternalLink(text[startPos .. <pos])


var tstream: StringStream = newStringStream()

proc filterHTML(origText: string): string =
    ## Scan through a Wiki page as HTML (Wikitext can have HTML tags mixed
    ## into it). Remove HTML tags, as well as the content of certain tags
    ## listed in SKIP_SPANS.
    let text = origText.replace(EMPTY_REF_RE, "<ref />")
    var xml: XmlParser

    # Quickly copy the text into the StringStream object
    shallowCopy(tstream.data, text)
    tstream.setPosition(0)

    result = newStringOfCap(text.len)
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
    result = newStringOfCap(text.len)
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
            let next2chars: string = text[pos .. pos+1]
            if next2chars == "{{" or next2chars == "{|":
                skipNestedChars(text, pos, '{', '}')

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

# ArticleData is an array that stores four string properties of a page: its
# title, its text content, its redirect value if it redirects to another page,
# and its namespace number. These are the XML values that we care about for
# each page.
type
    TagType = enum
        TITLE, TEXT, REDIRECT, NS
    ArticleData = array[TagType, string]

var RELEVANT_XML_TAGS = ["title", "text", "ns"]

proc handleArticle(article: ArticleData, tokenize: bool) =
    if article[NS] == "0" and article[REDIRECT] == "":
        if not tokenize:
            echo("= $1 =" % [article[TITLE]])
        # Parse the article inside a try/except block, discarding the errors
        # that appear due to occasional HTML that's flagrantly bad XML.
        try:
            let text = filterWikitext(filterHTML(article[TEXT]))
            if tokenize:
                let words = text.split(WORD_SEPARATOR_RE)
                for word in words:
                    if len(word) > 0:
                        echo(unicodeLower(word))
            else:
                echo(text.replace(BLANK_LINE_RE, "\n"))
        except IndexError:
            discard
        except RangeError:
            discard


proc readMediaWikiXML(input: Stream, tokenize: bool, filename="<input>") =
    ## Read the XML content that one actually downloads from Wikimedia,
    ## extracting the article content and sending it to the handleArticle()
    ## procedure.
    var xml: XmlParser
    var textBuffer: string = ""
    var article: ArticleData
    for tag in TITLE..NS:
        article[tag] = ""

    # Keep track of what text content represents. Is it article text, or a
    # similar text property of the page? Is it an attribute value on a tag that
    # we should pay attention to?
    var gettingText: bool = false
    var gettingAttribute: bool = false

    xml.open(input, filename, options={reportWhitespace})
    while true:
        # Scan through the XML, handling each token as it arrives.
        xml.next()
        case xml.kind
        of xmlElementStart, xmlElementOpen:
            if RELEVANT_XML_TAGS.contains(xml.elementName):
                # If this is a "title", "text", or "ns" tag, prepare to get its
                # text content. Move our writing pointer to the beginning of
                # the text buffer, so we can overwrite what was there.
                textBuffer.setLen(0)
                gettingText = true
            elif xml.elementName == "page":
                # If this is a new instance of the <page> tag that contains all
                # these tags, then reset the value that won't necessarily be
                # overridden, which is the redirect value.
                article[REDIRECT].setLen(0)
            elif xml.elementName == "redirect":
                # If this is the start of a redirect tag, prepare to get its
                # attribute value.
                gettingAttribute = true
        of xmlAttribute:
            # If we're looking for an attribute value, and we found one, add it
            # to the buffer.
            if gettingAttribute:
                textBuffer.add(xml.attrValue)
        of xmlCharData, xmlWhitespace:
            # If we're looking for text, and we found it, add it to the buffer.
            if gettingText:
                textBuffer.add(xml.charData)
        of xmlElementEnd:
            # When we reach the end of an element we care about, take the text
            # we've found and store it in the 'article' data structure. We can
            # accomplish this quickly by simply swapping their references.
            case xml.elementName
            of "title":
                swap article[TITLE], textBuffer
            of "text":
                swap article[TEXT], textBuffer
            of "redirect":
                swap article[REDIRECT], textBuffer
            of "ns":
                swap article[NS], textBuffer
            of "page":
                # When we reach the end of the <page> tag, send the article
                # data to handleArticle().
                handleArticle(article, tokenize)
            else:
                discard

            # Now that we've reached the end of an element, stop extracting
            # text. (We'll never need to extract text from elements that can
            # have other XML elements nested inside them.)
            gettingText = false
            gettingAttribute = false
        of xmlEof:
            break
        else:
            discard
    xml.close


const helptext: string = """
wiki2text - transform MediaWiki XML to text
Usage: wiki2text [-t] [-h]

Options:
-h	Show this help text
-t	Use a simple tokenizer, outputting one word per line
"""

proc writeHelp() =
    stderr.write(helptext)


when isMainModule:
    var
        tokenize: bool = false
        run: bool = true
    for kind, key, val in getopt():
        case kind
        of cmdLongOption, cmdShortOption:
            case key
            of "tokenize", "t":
                tokenize = true
            of "help", "h":
                writeHelp()
                run = false
            else:
                discard
        else:
            discard

    if run:
        readMediaWikiXML(newFileStream(stdin), tokenize)

