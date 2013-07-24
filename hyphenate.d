import std.algorithm, std.conv, std.range, std.ascii;
import std.stdio;

//enum HYPHEN = "&shy;";
enum HYPHEN = "-";

immutable(ubyte)[] getPriorities(string s)
{
    ubyte buf[20] = void;
    size_t pos = 0;
    foreach (ref i, c; s)
    {
        if (c.isDigit())
        {
            buf[pos++] = cast(ubyte)(c - '0');
            ++i;
        }
        else
        {
            buf[pos++] = 0;
        }
    }
    if (!s[$-1].isDigit())
        buf[pos++] = 0;
    assert(pos == s.count!(a => !a.isDigit())() + 1);
    while (pos && buf[pos-1] == 0)
        --pos;
    return buf[0..pos].idup;
}

unittest
{
    assert("a1bc3d4".getPriorities() == [0, 1, 0, 3, 4]);
    assert("to2gr".getPriorities() == [0, 0, 2]);
    assert("1to".getPriorities() == [1]);
    assert("x3c2".getPriorities() == [0, 3, 2]);
}

struct Trie
{
    static Leave empty;
    ref Leave getLeave(R)(R rng, bool force)
    {

        if (rng.empty)
            return leave;
        else
        {
            immutable c = rng.front; rng.popFront();
            if (auto p = c in elems)
                return p.getLeave(rng, force);
            else if (force)
            {
                elems[c] = Trie.init;
                return elems[c].getLeave(rng, force);
            }
            else
                return empty;
        }
    }

    Trie[dchar] elems;
    Leave leave;
}

struct Leave
{
    immutable(ubyte)[] priorities;
    string pattern;
}

struct Hyphenator
{
    string hyphenate(string word)
    {
        ubyte buf[20];
        const(ubyte)[] prios;
        if (auto p = word in exceptions)
            prios = *p;
        else
            prios = buildPrios(word, buf);

        string res;
        foreach (c, prio; zip(word, prios))
        {
            res ~= c;
            if (prio & 1) res ~= HYPHEN;
        }
        return res;
    }

    ubyte[] buildPrios(string word, ubyte[] buf)
    {
        auto search = chain(".", word, ".");
        size_t pos;
        for (; !search.empty; ++pos, search.popFront)
        {
            auto p = &root;
            foreach (c; search)
            {
                if ((p = c in p.elems) is null) break;
                foreach (off, prio; p.leave.priorities)
                    buf[pos + off] = max(buf[pos + off], prio);
            }
        }
        // no hyphens in the first/last two chars
        buf[1] = buf[2] = buf[pos-1] = buf[pos-2] = 0;
        return buf[2..pos];
    }

    Leave findLeave(R)(R rng)
    {
        return root.getLeave(rng, false);
    }

    void insertPattern(string s)
    {
        auto leave = &root.getLeave(s.filter!(a => !a.isDigit()), true);
        leave.priorities = s.getPriorities();
        leave.pattern = s;
    }

    void insertException(string s)
    {
        auto prios = exceptionPriorities(s);
        s = s.filter!(a => a != '-').to!string();
        exceptions[s] = prios;
    }

    static immutable(ubyte)[] exceptionPriorities(string s)
    {
        immutable(ubyte)[] prios;
        assert(s.front != '-');
        foreach (ref i, c; s[1..$])
        {
            if (c == '-')
                prios ~= 1, ++i;
            else
                prios ~= 0;
        }
        prios ~= 0;
        return prios;
    }

    unittest
    {
        assert(exceptionPriorities("as-so-ciate") == [0, 1, 0, 1, 0, 0, 0, 0, 0], exceptionPriorities("as-so-ciate").to!string());
    }

    immutable(ubyte)[][string] exceptions;
    Trie root;
}

Hyphenator hyphenator(string s)
{
    Hyphenator hyphenator;
    auto lines = s.splitter("\n");
    lines = lines.find!(a => a.startsWith(`\patterns{`))();
    lines.popFront();
    foreach (line; refRange(&lines).until!(a => a.startsWith("}"))())
    {
        hyphenator.insertPattern(line);
    }
    assert(lines.front.startsWith("}"));
    lines.popFront();
    assert(lines.front.startsWith(`\hyphenation{`));
    lines.popFront();
    foreach (line; refRange(&lines).until!(a => a.startsWith("}"))())
    {
        hyphenator.insertException(line);
    }
    assert(lines.front.startsWith("}"));
    lines.popFront();
    assert(lines.front.empty);
    lines.popFront();
    assert(lines.empty);
    return hyphenator;
}

void main(string[] args)
{
    auto h = hyphenator(import("hyphen.tex"));
    foreach (word; args[1..$])
        writeln(h.hyphenate(word));
}
