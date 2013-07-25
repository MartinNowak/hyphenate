import std.algorithm, std.conv, std.range, std.ascii;
import std.stdio;
import core.bitop;

//enum HYPHEN = "&shy;";
enum HYPHEN = "-";

debug
{
    struct Priorities
    {
        string pattern;
        immutable(ubyte)[] prios;
        alias prios this;
    }
}
else
{
    alias Priorities = immutable(ubyte)[];
}

@property auto letters(string s) { return s.filter!(a => !a.isDigit())(); }
@property auto priorities(R)(R r) { return r.getPriorities(); }

extern(C) void* _aaGetX(void** pp, const TypeInfo keyti, in size_t valuesize, void* pkey);

@property ref V getLvalue(AA : V[K], K, V)(ref AA aa, K key)
{
    return *cast(V*)_aaGetX(cast(void**)&aa, typeid(K), V.sizeof, &key);
}

immutable(ubyte)[] getPriorities(R)(R r) if (is(ElementType!R : dchar))
{
    ubyte buf[20] = void;
    size_t pos = 0;
    while (!r.empty)
    {
        immutable c = r.front; r.popFront();
        if (c.isDigit())
        {
            buf[pos++] = cast(ubyte)(c - '0');
            if (!r.empty) r.popFront();
        }
        else
        {
            buf[pos++] = 0;
        }
    }
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
    this(dchar c)
    {
        debug _c = c;
    }

    static struct Table
    {
        inout(Trie)* opIn_r(dchar c) inout
        {
            if (c >= 128 || !bt(bitmaskPtr, c))
                return null;
            return &entries[getPos(c)-1];
        }

        ref Trie getLvalue(dchar c)
        {
            if (c >= 128) assert(0);
            auto npos = getPos(c);
            if (!bts(bitmaskPtr, c))
                entries.insertInPlace(npos++, Trie(c));
            return entries[npos-1];
        }

        private size_t getPos(dchar c) const
        {
            immutable nbyte = c / 32; c &= 31;
            size_t npos;
            foreach (i; 0 .. nbyte)
                npos += popcnt(bitmask[i]);
            npos += popcnt(bitmask[nbyte] & (1 << c | (1 << c) - 1));
            return npos;
        }

        private @property inout(size_t)* bitmaskPtr() inout
        {
            return cast(inout(size_t)*)bitmask.ptr;
        }

        uint[4] bitmask;
        Trie[] entries;
    }
    debug dchar _c;
    Priorities priorities;
    version (none)
        Trie[dchar] elems;
    else
        Table elems;
}

struct Hyphenator
{
    string hyphenate(string word) const
    {
        ubyte buf[20];
        const(ubyte)[] prios;
        if (auto p = word in exceptions)
            prios = *p;
        else
            prios = buildPrios(word, buf);

        string res;
        assert(prios.length == word.length-1);
        res ~= word.front; word.popFront();
        foreach (c, prio; zip(word, prios))
        {
            if (prio & 1) res ~= HYPHEN;
            res ~= c;
        }
        return res;
    }

    ubyte[] buildPrios(string word, ubyte[] buf) const
    {
        auto search = chain(".", word, ".");
        assert(buf.length >= word.length + 3);
        for (size_t pos; !search.empty; ++pos, search.popFront())
        {
            auto p = &root;
            foreach (c; search)
            {
                if ((p = c in p.elems) is null) break;
                foreach (off, prio; p.priorities)
                    buf[pos + off] = max(buf[pos + off], prio);
            }
        }
        // trim priorities before and after leading '.'
        // trim priorities before and after trailing '.'
        buf = buf[2..2+word.length-1];
        // no hyphens after first or before last letter
        buf[0] = buf[$-1] = 0;
        return buf;
    }

    Leave findLeave(R)(R rng)
    {
        return root.getLeave(rng, false);
    }

    void insertPattern(R)(R rng)
    {
        auto p = &getTerminal(rng.letters);
        *p = rng.priorities;
        debug { p.pattern = rng.to!string(); }
    }

    private ref Priorities getTerminal(R)(R rng)
    {
        auto p = &root;
        foreach (c; rng)
            p = &p.elems.getLvalue(c);
        return p.priorities;
    }

    void insertException(string s)
    {
        auto prios = exceptionPriorities(s);
        s = s.filter!(a => a != '-')().to!string();
        exceptions[s] = prios;
    }

    static Priorities exceptionPriorities(string s)
    {
        Priorities prios;
        for (s.popFront(); !s.empty; s.popFront())
        {
            if (s.front == '-')
                prios ~= 1, s.popFront();
            else
                prios ~= 0;
        }
        return prios;
    }

    unittest
    {
        assert(exceptionPriorities("as-so-ciate") == [0, 1, 0, 1, 0, 0, 0, 0]);
    }

    Priorities[string] exceptions;
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
