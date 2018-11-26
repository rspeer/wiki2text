# wiki2text (unmaintained)

I don't work on this project anymore, and the Nim language has probably moved
far beyond the version I used to make this. You may be able to make it work for
you, but no guarantees.

I now work on a full-blown LL parser for wikitext,
[wikiparsec](https://github.com/LuminosoInsight/wikiparsec).

# Original introduction

**What you put in:** a .xml.bz2 file downloaded from Wikimedia

**What you get out**: gigabytes of clean natural language text

wiki2text is a fast pipeline that takes a MediaWiki XML dump -- such as the
exports of Wikipedia that you can download from [dumps.wikimedia.org][] -- and
extract just the natural-language text from them, skipping the Wiki formatting
characters and the HTML tags.

This is particularly useful as a way to get free corpora, in many languages,
for natural language processing.

The only formatting you will get is that the titles of new articles and new
sections will appear on lines that start and end with some number of `=` signs.
I've found it useful to distinguish titles from body text. If you don't need
this, these lines are easy to exclude using `grep -v`.

wiki2text is written with these goals in mind:

- Clean code that is clear about what it's doing
- Doing no more than is necessary
- Being incredibly fast (it parses an entire Wikipedia in minutes)
- Being usable as a step in a pipeline

Thanks to def-, a core Nim developer, for making optimizations that make the
code so incredibly fast.

[dumps.wikimedia.org]: https://dumps.wikimedia.org/backup-index.html

## Why Nim?

Why is this code written in a fast-moving, emerging programming language? It's
an adaptation of a Python script that took *days* to run. Nim allowed me to
keep the understandability of Python but also have the speed of C.

## Setup

wiki2text needs to be compiled using Nim 0.11. Install it by following the
directions on [Nim's download page][].

[Nim's download page]: http://nim-lang.org/download.html

You can build Nim from this repository by running:

    make

You can also install it using Nimble, Nim's package manager, instead:

    nimble install wiki2text

## Usage

Download one of the database dumps from [dumps.wikimedia.org][]. The filename
you want should be the one of the form `*-pages-articles.xml.bz2`. These files
can be many gigabytes in size, so you might want to start with a language besides
English, with a smaller number of articles.

But suppose you did download `enwiki-DATE-pages-articles.xml.bz2`. Then you should
run:

    bunzip2 -c enwiki-DATE-pages-articles.xml.bz2 | ./wiki2text > enwiki.txt

To skip all headings, run:

    bunzip2 -c enwiki-DATE-pages-articles.xml.bz2 | ./wiki2text | grep -v '^=' > enwiki.txt

enwiki.txt will fill up with article text as quickly as it comes out of `bunzip2`.

## Example output

Here's an example of part of the text that comes out of the English Wikipedia
(with hard line wrapping added):

    = Albedo =

    Albedo (), or reflection coefficient, derived from Latin albedo "whiteness"
    (or reflected sunlight) in turn from albus "white", is the diffuse
    reflectivity or reflecting power of a surface. It is the ratio of reflected
    radiation from the surface to incident radiation upon it. Its dimensionless
    nature lets it be expressed as a percentage and is measured on a scale from
    zero for no reflection of a perfectly black surface to 1 for perfect
    reflection of a white surface.

    Albedo depends on the frequency of the radiation. When quoted unqualified,
    it usually refers to some appropriate average across the spectrum of
    visible light. In general, the albedo depends on the directional
    distribution of incident radiation, except for Lambertian surfaces, which
    scatter radiation in all directions according to a cosine function and
    therefore have an albedo that is independent of the incident distribution.
    In practice, a bidirectional reflectance distribution function (BRDF) may
    be required to accurately characterize the scattering properties of a
    surface, but albedo is very useful as a first approximation.

    The albedo is an important concept in climatology, astronomy, and
    calculating reflectivity of surfaces in LEED sustainable-rating systems for
    buildings. The average overall albedo of Earth, its planetary albedo, is 30
    to 35% because of cloud cover, but widely varies locally across the surface
    because of different geological and environmental features.

    The term was introduced into optics by Johann Heinrich Lambert in his 1760
    work Photometria.

    ==Terrestrial albedo==

    Albedos of typical materials in visible light range from up to 0.9 for
    fresh snow to about 0.04 for charcoal, one of the darkest substances.
    Deeply shadowed cavities can achieve an effective albedo approaching the
    zero of a black body. When seen from a distance, the ocean surface has a
    low albedo, as do most forests, whereas desert areas have some of the
    highest albedos among landforms. Most land areas are in an albedo range of
    0.1 to 0.4. The average albedo of the Earth is about 0.3. This is far
    higher than for the ocean primarily because of the contribution of clouds.
    Earth's surface albedo is regularly estimated via Earth observation
    satellite sensors such as NASA's MODIS instruments on board the Terra and
    Aqua satellites. As the total amount of reflected radiation cannot be
    directly measured by satellite, a mathematical model of the BRDF is used to
    translate a sample set of satellite reflectance measurements into estimates
    of directional-hemispherical reflectance and bi-hemispherical reflectance
    (e.g.).

    Earth's average surface temperature due to its albedo and the greenhouse
    effect is currently about 15°C. If Earth were frozen entirely (and hence be
    more reflective) the average temperature of the planet would drop below
    −40°C. If only the continental land masses became covered by glaciers, the
    mean temperature of the planet would drop to about 0°C. In contrast, if the
    entire Earth is covered by water—a so-called aquaplanet—the average
    temperature on the planet would rise to just under 27°C.

## Limitations

You may notice that occasional words and phrases are missing from the text.
These are the parts of the article that come from MediaWiki templates.

Templates are an incredibly complicated, Turing-complete subset of MediaWiki,
and are used for everything from simple formatting to building large infoboxes,
tables, and navigation boxes.

It would be nice if we could somehow keep only the simple ones and discard
the complex ones, but what's easiest to do is to simply ignore every template.

Sometimes templates contain the beginnings or ends of HTML or Wikitable
formatting that we would normally skip, in which case extra crud may show up in
the article.

This probably doesn't work very well for wikis that have specific, meaningful
formatting, such as Wiktionary. The [conceptnet5][] project includes a slow
Wiktionary parser in Python that you might be able to use.

[conceptnet5]: https://github.com/commonsense/conceptnet5

