module clang_related;

import clang;
import std.conv: to;

TranslationUnit parseFile(string filename, in string[] args)
{
    enum flags =
          TranslationUnitFlags.SkipFunctionBodies
        | TranslationUnitFlags.IgnoreNonErrorsFromIncludedFiles
        | TranslationUnitFlags.KeepGoing; //Do not stop processing when fatal errors are encountered

    return parse(filename, args); //, flags);
}

private struct Key
{
    enum Kind
    {
        Variable, // or struct or type
        Function,
        Elaborated,
    }

    Kind kind;
    string name;
}

/*private*/ Cursor[Key] addedDecls;

version(DebugOutput)  import std.stdio;

void checkAndAdd(ref Cursor cur)
{
    import std.algorithm.comparison: equal;

    version(DebugOutput) cur.underlyingType.writeln;

    Key.Kind kind;

    if(cur.kind == Cursor.Kind.FunctionDecl)
        kind = Key.Kind.Function;
    else if(cur.underlyingType.isInvalid)
        kind = Key.Kind.Elaborated;

    Key key = { name: cur.spelling, kind: kind };

    auto found = (key in addedDecls);

    import std.stdio;

    if(found is null)
    {
        writeln(cur, " not found");

        addedDecls[key] = cur;
    }
    else
        cmpCursors(key, *found, cur);
}

private void cmpCursors(Key key, Cursor old_orig, Cursor new_orig)
{
    version(DebugOutput) writeln(">>>> Check found:\n", old_orig, "\n", new_orig);

    const needCompareDefs = old_orig.isDefinition || new_orig.isDefinition;
    const needReplaceDeclByDef = (!old_orig.isDefinition && new_orig.isDefinition);

    Cursor _old;
    Cursor _new;

    if(needCompareDefs)
    {
        _old = old_orig.definition;
        _new = new_orig.definition;
    }
    else
    {
        _old = old_orig;
        _new = new_orig;
    }

    version(DebugOutput) writeln("Compares:\n", new_orig, "\n", old_orig, "\nneed replace=", needReplaceDeclByDef);

    const oldHash = _old.calcIndependentHash;
    const newHash = _new.calcIndependentHash;

    if(oldHash == newHash)
    {
        if(needReplaceDeclByDef)
            addedDecls[key] = new_orig;
    }
    else
    {
        const osr = old_orig.getSourceRange;
        const nsr = new_orig.getSourceRange;

        throw new Exception(
            "New cursor is not equal to previously saved:\n"
            ~"Old: "~osr.fileLinePrettyString~"\n"
            ~old_orig.getPrettyPrinted~"\n"
            ~"New: "~nsr.fileLinePrettyString~"\n"
            ~new_orig.getPrettyPrinted~"\n"
            ~"Old orig cursor: "~old_orig.toString~"\n"
            ~"New orig cursor: "~new_orig.toString~"\n"
            ~"Hash old: "~oldHash.to!string~"\n"
            ~"Hash new: "~newHash.to!string
        );
    }
}

private auto calcIndependentHash(in Cursor c)
{
    import clang.c.index;
    import std.digest.murmurhash;
    import std.string;
    import std.stdio;

    MurmurHash3!(128, 64) acc;

    ChildVisitResult calcHash(in Cursor cur, in Cursor parent)
    {
        acc.put(cur.toString.representation);
        acc.put(cur.toString.representation);

        return ChildVisitResult.Recurse;
    }

    calcHash(c, c);
    c.visitChildren(&calcHash);

    return acc.finish();
}

string getPrettyPrinted(in Cursor cur)
{
    import clang.c.index;

    return cur.cx.clang_getCursorPrettyPrinted(null).toString;
}

private auto getSourceRange(in Cursor c)
{
    import clang.c.index;

    //TODO: make libclang _sourceRangeCreate public

    return SourceRange(clang_getCursorExtent(c.cx));
}

private string fileLinePrettyString(in SourceRange r)
{
    return r.path~":"~r.start.line.to!string~":"~r.start.column.to!string;
}
