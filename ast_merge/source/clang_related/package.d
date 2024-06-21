module clang_related;

//~ import clang.c.index: CXType_Pointer;
import clang;

TranslationUnit parseFile(string filename, in string[] args)
{
    enum flags =
          TranslationUnitFlags.SkipFunctionBodies
        | TranslationUnitFlags.IgnoreNonErrorsFromIncludedFiles;

    return parse(filename, args, flags);
}

/*private*/ Cursor*[string] addedDecls;

Cursor* checkAndAdd(ref Cursor cur)
{
    return addedDecls.getOrAdd!(() => &cur)(cur.spelling);
}

private:

import std.traits: isAssociativeArray;

private auto getOrAdd(alias factory, AA, I)(ref AA arr, I idx)
if(isAssociativeArray!AA)
{
    auto found = (idx in arr);

    if(found is null)
    {
        auto v = factory();
        arr[idx] = v;
        found = (idx in arr);
    }

    return *found;
}
