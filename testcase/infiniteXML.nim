import math, strutils

const IDENT_CHARACTERS = "abcdefg"
const TEXT_CHARACTERS = "hijklmnopqrstuvwxyz. \n"
const ENTITIES = ["&lt;", "&amp;", "&gt;", "&quot;", "&#x1F639;"]

proc outputTag(depth: int)

proc outputText() =
    var rand, rand2: int
    var n_pieces: int = pow(random(10.0), 2).toInt
    for i in 1..n_pieces:
        rand2 = random(100)
        if rand2 == 0:
            rand = random(ENTITIES.len)
            stdout.write(ENTITIES[rand])
        else:
            rand = random(TEXT_CHARACTERS.len)
            stdout.write(TEXT_CHARACTERS[rand])

proc outputIdent(): string =
    var ident = ""
    var rand: int
    var n_pieces: int = random(10) + 1
    for i in 1..n_pieces:
        rand = random(IDENT_CHARACTERS.len)
        ident.add(IDENT_CHARACTERS[rand])
    stdout.write(ident)
    return ident

proc outputComment() =
    stdout.write("<!-- ")
    outputText()
    stdout.write(" -->")

proc outputAttributes() =
    var n_pieces: int = pow(random(2.0), 3).toInt
    for i in 1..n_pieces:
        stdout.write(" ")
        discard outputIdent()
        stdout.write("=\"")
        discard outputIdent()
        stdout.write("\"")

proc outputAssortedMarkup(depth: int) =
    var rand: int
    var n_objects: int = random(100.0 / (depth + 1).toFloat).toInt
    for i in 1..n_objects:
        rand = random(20)
        if rand == 0:
            outputComment()
        elif rand <= 10:
            outputTag(depth + 1)
        else:
            outputText()

proc outputTag(depth: int) =
    let rand = random(20)
    stdout.write("<")
    let tag = outputIdent()
    outputAttributes()
    if rand == 0:
        stdout.write(" />")
    else:
        stdout.write(">")
        outputAssortedMarkup(depth)
        stdout.write("</$1>" % tag)

stdout.write("<xml>")
while true:
    outputTag(0)
