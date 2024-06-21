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
    bool isElaborated;
    string name;
}

/*private*/ Cursor*[Key] addedDecls;

void checkAndAdd(ref Cursor cur)
{
    import std.stdio;
    cur.underlyingType.writeln;

    Key key = { name: cur.spelling, isElaborated: cur.underlyingType.isInvalid };

    auto found = (key in addedDecls);

    import std.stdio;

    if(found is null)
    {
        writeln(cur, " not found");

        addedDecls[key] = &cur;
    }
    else
    {
        writeln(">>>> Check found:\n", cur, "\n", **found);

        Cursor newCur = cur;
        const needReplaceDeclByDef = (!(*found).isDefinition && cur.isDefinition);

        if(!(*found).isDefinition)
            newCur = cur.type.declaration;

        Cursor _old = (**found).getCursorForCmp;
        Cursor _new = newCur.getCursorForCmp;

        writeln("Compares:\n", _new, "\n", _old, "\nneed replace=", needReplaceDeclByDef);

        if(_old == _new)
        {
            if(needReplaceDeclByDef)
                addedDecls[key] = &cur;
        }
        else
        {
            const osr = cur.getSourceRange;
            const nsr = (**found).getSourceRange;

            throw new Exception(
                "New cursor is not equal to previously saved:\n"
                ~"Old: "~osr.fileLinePrettyString~"\n"
                ~_old.getPrettyPrinted~"\n"
                ~"New: "~nsr.fileLinePrettyString~"\n"
                ~_new.getPrettyPrinted~"\n"
                ~(*found).toString~"\n"
                ~cur.toString
            );
        }
    }
}

private auto getCursorForCmp(ref Cursor c)
{
    auto d = c.definition;

    if(!d.isNull)
        return d;

    return c.canonical;
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
