/**
   Copyright: Martin Nowak 2013-.
   License: MIT License, see LICENSE
   Authors: $(WEB code.dawg.eu, Martin Nowak)
*/
module example;

import hyphenate;
import std.path : extension;

/// inserted hyphen character
enum HYPHEN =  "&shy;";

/// global immutable instance initialized for en-US
static immutable Hyphenator h;
shared static this()
{
    h = cast(immutable)Hyphenator(import("hyphen.tex"));
}

/// hyphenate a words in a text file
string hyphenateWords(string s)
{
    import std.regex;

    enum wordsRE = ctRegex!(`\w+`, "g");
    return s.replace!((c) => h.hyphenate(c.hit, HYPHEN))(wordsRE);
}

/// hyphenate a HTML file
string hyphenateHTML(string s)
{
    return s;
}

/**
   Parameters: list of files

   Replaces files with a hyphenated version
*/
void main(string[] args)
{
    import std.file;

    foreach (file; args[1..$])
    {
        if (file.extension == ".html")
            write(file, file.readText.hyphenateHTML());
        else
            write(file, file.readText.hyphenateWords());
    }
}
